const crypto = require('node:crypto');

// ============================================================
// MOVERA RIDER V2 — FRENCH PHONE AUTHENTICATION
// Backend OTP prototype — local development only
// ============================================================

const otpSessions = new Map();
const riders = new Map();
const refreshSessions = new Map();
const requestLimits = new Map();

const OTP_DURATION_MS = 5 * 60 * 1000;
const OTP_RETRY_MS = 60 * 1000;
const OTP_MAX_ATTEMPTS = 5;
const OTP_MAX_REQUESTS = 3;
const OTP_WINDOW_MS = 15 * 60 * 1000;

const secret = crypto.randomBytes(32);

function normalizeFrenchPhone(input) {
  if (typeof input !== 'string') return null;
  const phone = input.trim().replace(/[\s().-]/g, '');
  if (/^0[67]\d{8}$/.test(phone)) return '+33' + phone.substring(1);
  if (/^\+33[67]\d{8}$/.test(phone)) return phone;
  if (/^0033[67]\d{8}$/.test(phone)) return '+' + phone.substring(2);
  return null;
}

function otpHash(sessionId, code) {
  return crypto.createHmac('sha256', secret).update(`${sessionId}:${code}`).digest();
}

function cleanupExpiredSessions(now) {
  for (const [id, challenge] of otpSessions) {
    if (now >= challenge.expiresAt) otpSessions.delete(id);
  }
  for (const [phone, limit] of requestLimits) {
    if (now - limit.windowStart >= OTP_WINDOW_MS) requestLimits.delete(phone);
  }
}

function isDebugOtpAllowed() {
  return process.env.NODE_ENV !== 'production' && process.env.MOVERA_DEBUG_OTP === '1';
}

function requestOtp(body = {}) {
  const payload = body && typeof body === 'object' ? body : {};
  const phone = normalizeFrenchPhone(payload.phone);

  if (!phone) {
    return {
      status: 400,
      body: { code: 'INVALID_FRENCH_PHONE', message: 'Enter a valid French mobile number.' },
    };
  }

  if (payload.linkToken) {
    return { status: 501, body: { code: 'PROVIDER_LINK_NOT_IMPLEMENTED' } };
  }

  if (!isDebugOtpAllowed()) {
    return {
      status: 503,
      body: { code: 'SMS_PROVIDER_NOT_CONFIGURED', message: 'SMS authentication is not configured.' },
    };
  }

  const now = Date.now();
  cleanupExpiredSessions(now);

  let limit = requestLimits.get(phone);
  if (!limit) {
    limit = { windowStart: now, lastSentAt: 0, count: 0 };
  }

  const wait = OTP_RETRY_MS - (now - limit.lastSentAt);
  if (wait > 0) {
    return {
      status: 429,
      body: {
        code: 'OTP_TOO_SOON',
        message: 'Please wait before requesting another code.',
        retryAfterSeconds: Math.ceil(wait / 1000),
      },
    };
  }

  if (limit.count >= OTP_MAX_REQUESTS) {
    return { status: 429, body: { code: 'OTP_RATE_LIMITED', message: 'Too many OTP requests.' } };
  }

  limit.count += 1;
  limit.lastSentAt = now;
  requestLimits.set(phone, limit);

  for (const [id, challenge] of otpSessions) {
    if (challenge.phone === phone) otpSessions.delete(id);
  }

  const sessionId = crypto.randomUUID();
  const code = String(crypto.randomInt(0, 10000)).padStart(4, '0');
  const expiresAt = now + OTP_DURATION_MS;

  otpSessions.set(sessionId, {
    phone,
    hash: otpHash(sessionId, code),
    expiresAt,
    attempts: 0,
  });

  console.log('');
  console.log('==========================================');
  console.log(' MOVERA RIDER - DEVELOPMENT OTP');
  console.log(' Phone:', phone);
  console.log(' Code:', code);
  console.log(' Expires in: 5 minutes');
  console.log('==========================================');
  console.log('');

  return {
    status: 200,
    body: {
      code: 'OK',
      sessionId,
      expiresAt: new Date(expiresAt).toISOString(),
      retryAfterSeconds: 60,
    },
  };
}

function verifyOtp(body = {}) {
  const payload = body && typeof body === 'object' ? body : {};
  const phone = normalizeFrenchPhone(payload.phone);
  const { sessionId, code } = payload;

  if (
    !phone ||
    typeof sessionId !== 'string' ||
    !sessionId ||
    typeof code !== 'string' ||
    !/^\d{4}$/.test(code)
  ) {
    return { status: 400, body: { code: 'INVALID_OTP_REQUEST' } };
  }

  if (payload.linkToken) {
    return { status: 501, body: { code: 'PROVIDER_LINK_NOT_IMPLEMENTED' } };
  }

  if (!isDebugOtpAllowed()) {
    return { status: 503, body: { code: 'SMS_PROVIDER_NOT_CONFIGURED' } };
  }

  const challenge = otpSessions.get(sessionId);
  if (!challenge || challenge.phone !== phone) {
    return { status: 400, body: { code: 'OTP_INVALID', message: 'Invalid verification code.' } };
  }

  if (Date.now() >= challenge.expiresAt) {
    otpSessions.delete(sessionId);
    return { status: 400, body: { code: 'OTP_EXPIRED', message: 'The verification code has expired.' } };
  }

  if (challenge.attempts >= OTP_MAX_ATTEMPTS) {
    otpSessions.delete(sessionId);
    return { status: 429, body: { code: 'OTP_ATTEMPTS_EXCEEDED' } };
  }

  challenge.attempts += 1;
  const receivedHash = otpHash(sessionId, code);
  const valid = crypto.timingSafeEqual(challenge.hash, receivedHash);

  if (!valid) {
    if (challenge.attempts >= OTP_MAX_ATTEMPTS) {
      otpSessions.delete(sessionId);
      return { status: 429, body: { code: 'OTP_ATTEMPTS_EXCEEDED' } };
    }
    return { status: 400, body: { code: 'OTP_INVALID', message: 'Incorrect verification code.' } };
  }

  otpSessions.delete(sessionId);

  const isNewRider = !riders.has(phone);
  if (isNewRider) {
    riders.set(phone, {
      id: crypto.randomUUID(),
      phone,
      phoneVerified: true,
      createdAt: new Date().toISOString(),
      profileCompleted: false,
    });
  }

  const rider = riders.get(phone);
  const accessToken = crypto.randomBytes(32).toString('hex');
  const refreshToken = crypto.randomBytes(32).toString('hex');

  refreshSessions.set(refreshToken, {
    riderId: rider.id,
    createdAt: Date.now(),
  });

  return {
    status: 200,
    body: {
      code: 'OK',
      accessToken,
      refreshToken,
      isNewRider,
    },
  };
}

module.exports = {
  requestOtp,
  verifyOtp,
  normalizeFrenchPhone,
};
