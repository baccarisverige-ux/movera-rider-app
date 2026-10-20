const http = require('http');
const { quote } = require('./modules/pricing');
const safety = require('./modules/safety');
const auth = require('./modules/auth');

const idempotency = new Map();
const rides = new Map();
const pushDevices = new Map();
const paymentIntents = new Map();
const accountSecurity = {
  phone: '',
  email: '',
  phoneVerifiedAt: null,
  emailVerifiedAt: null,
  passkeyEnabled: false,
  twoStepEnabled: false,
  authenticatorEnabled: false,
  passwordUpdatedAt: null,
  recoveryPhone: null,
  googleConnected: false,
  appleConnected: false,
  reauthenticatedAt: null,
  capabilities: {
    passkeys: false,
    password: false,
    authenticator: false,
    twoStep: false,
    recoveryPhone: false,
    connectedAccounts: false,
    reauthentication: false,
    signOutOtherDevices: false,
  },
  sessions: [
    {
      id: 'session_current',
      device: 'This device',
      place: '',
      source: 'Movera',
      current: true,
    },
  ],
};

function send(res, status, body, requestId) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('X-Request-Id', requestId);
  res.setHeader('X-Api-Version', 'v1');
  res.end(JSON.stringify({ ...body, requestId }));
}

function readBody(req) {
  return new Promise((resolve) => {
    let raw = '';
    req.on('data', (c) => (raw += c));
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        resolve({});
      }
    });
  });
}

function nearby(ride) {
  const lat = ride && typeof ride.pickupLat === 'number' ? ride.pickupLat : null;
  const lng = ride && typeof ride.pickupLng === 'number' ? ride.pickupLng : null;
  if (lat == null || lng == null) return [];
  return [
    { id: 'veh_a', lat: lat + 0.0021, lng: lng - 0.0014, bearing: 42 },
    { id: 'veh_b', lat: lat - 0.0016, lng: lng + 0.0022, bearing: 210 },
    { id: 'veh_c', lat: lat + 0.0008, lng: lng + 0.0018, bearing: 128 },
  ];
}

const server = http.createServer(async (req, res) => {
  const requestId =
    req.headers['x-request-id'] || Math.random().toString(16).slice(2);
  const url = req.url.split('?')[0];
  const method = (req.method || 'GET').toUpperCase();
  const key = req.headers['idempotency-key'];

  if (key && idempotency.has(key)) {
    send(res, 200, idempotency.get(key), requestId);
    return;
  }

  if (url === '/health' && method === 'GET') {
    send(res, 200, { ok: true }, requestId);
    return;
  }

  // --- NOUVELLES ROUTES AUTHENTIFICATION ---
  if (url === '/api/v1/auth/otp/request' && method === 'POST') {
    const body = await readBody(req);
    const result = auth.requestOtp(body);
    send(res, result.status, result.body, requestId);
    return;
  }

  if (url === '/api/v1/auth/otp/verify' && method === 'POST') {
    const body = await readBody(req);
    const result = auth.verifyOtp(body);
    send(res, result.status, result.body, requestId);
    return;
  }

  if (url === '/api/v1/auth/sign-out' && method === 'POST') {
    send(res, 200, { code: 'OK' }, requestId);
    return;
  }

  // --- PUSH NOTIFICATIONS ---
  if (url === '/api/v1/push/devices' && method === 'POST') {
    const body = await readBody(req);
    const token = typeof body.token === 'string' ? body.token.trim() : '';
    const platform =
      typeof body.platform === 'string' ? body.platform.trim() : '';
    if (!token || body.provider !== 'fcm' || !platform) {
      send(res, 400, { code: 'INVALID_PUSH_DEVICE' }, requestId);
      return;
    }
    pushDevices.set(token, {
      token,
      provider: 'fcm',
      platform,
      updatedAt: new Date().toISOString(),
    });
    send(res, 200, { code: 'OK', status: 'registered' }, requestId);
    return;
  }

  if (url === '/api/v1/push/devices/unregister' && method === 'POST') {
    const body = await readBody(req);
    const token = typeof body.token === 'string' ? body.token.trim() : '';
    if (!token) {
      send(res, 400, { code: 'INVALID_PUSH_DEVICE' }, requestId);
      return;
    }
    pushDevices.delete(token);
    send(res, 200, { code: 'OK', status: 'unregistered' }, requestId);
    return;
  }

  if (url === '/api/v1/account/security' && method === 'GET') {
    send(res, 200, { code: 'OK', security: accountSecurity }, requestId);
    return;
  }

  if (
    url === '/api/v1/account/security/sessions/sign-out-others' &&
    method === 'POST'
  ) {
    const reauthenticatedAt = accountSecurity.reauthenticatedAt
      ? new Date(accountSecurity.reauthenticatedAt)
      : null;
    const ageMs = reauthenticatedAt
      ? Date.now() - reauthenticatedAt.getTime()
      : Number.POSITIVE_INFINITY;
    const fresh =
      Number.isFinite(ageMs) && ageMs >= 0 && ageMs <= 5 * 60 * 1000;
    if (!fresh) {
      send(
        res,
        403,
        {
          code: 'REAUTH_REQUIRED',
          message: 'Fresh reauthentication is required.',
        },
        requestId,
      );
      return;
    }
    accountSecurity.sessions = accountSecurity.sessions.filter(
      (session) => session.current === true,
    );
    accountSecurity.reauthenticatedAt = null;
    send(res, 200, { code: 'OK', security: accountSecurity }, requestId);
    return;
  }

  if (url === '/api/v1/quotes' && method === 'POST') {
    const body = await readBody(req);
    const payload = { code: 'OK', quote: quote(body) };
    if (key) idempotency.set(key, payload);
    send(res, 200, payload, requestId);
    return;
  }

  if (url === '/api/v1/rides' && method === 'POST') {
    const body = await readBody(req);
    const ride = {
      id: `ride_${Date.now()}`,
      status: body.scheduledAt ? 'bookingRequested' : 'findingDriver',
      rideType: body.rideType || 'movera',
      price: body.price,
      paymentMethod: body.paymentMethod,
      pickupAddress: body.pickupAddress,
      destinationAddress: body.destinationAddress,
      pickupLat: body.pickupLat,
      pickupLng: body.pickupLng,
      destinationLat: body.destinationLat,
      destinationLng: body.destinationLng,
      scheduledAt: body.scheduledAt,
    };
    rides.set(ride.id, ride);
    const payload = { code: 'OK', ride };
    if (key) idempotency.set(key, payload);
    send(res, 200, payload, requestId);
    return;
  }

  const parts = url.split('/').filter(Boolean);
  if (parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'rides' && parts[3]) {
    const id = parts[3];
    const ride = rides.get(id);

    if (parts.length === 4 && method === 'GET') {
      if (!ride) {
        send(res, 404, { code: 'NOT_FOUND', message: 'Ride not found' }, requestId);
        return;
      }
      send(res, 200, { code: 'OK', ride }, requestId);
      return;
    }

    if (parts[4] === 'cancel' && method === 'POST') {
      const body = await readBody(req);
      if (!ride) {
        send(res, 404, { code: 'NOT_FOUND' }, requestId);
        return;
      }
      if (ride.status !== 'cancelledByRider') {
        ride.status = 'cancelledByRider';
        if (typeof body.reason === 'string') ride.cancellationReason = body.reason;
      }
      const payload = { code: 'OK', ride };
      if (key) idempotency.set(key, payload);
      send(res, 200, payload, requestId);
      return;
    }

    if (parts[4] === 'nearby' && method === 'GET') {
      send(res, 200, { code: 'OK', vehicles: nearby(ride) }, requestId);
      return;
    }

    if (parts[4] === 'status' && method === 'POST') {
      const body = await readBody(req);
      const next = ride || { id };
      next.status = body.status || next.status;
      if (body.driver) next.driver = body.driver;
      if (body.lat != null) next.driverLat = body.lat;
      if (body.lng != null) next.driverLng = body.lng;
      rides.set(id, next);
      const payload = { code: 'OK', ride: next };
      if (key) idempotency.set(key, payload);
      send(res, 200, payload, requestId);
      return;
    }

    if (parts.length === 4 && method === 'PATCH') {
      const body = await readBody(req);
      if (!ride) {
        send(res, 404, { code: 'NOT_FOUND' }, requestId);
        return;
      }
      if (body.price != null) ride.price = body.price;
      if (body.offerIncreaseKr != null) ride.offerIncreaseKr = body.offerIncreaseKr;
      ride.status = 'findingDriver';
      const payload = { code: 'OK', ride };
      if (key) idempotency.set(key, payload);
      send(res, 200, payload, requestId);
      return;
    }
  }

  if (url === '/api/v1/payments' && method === 'POST') {
    const body = await readBody(req);
    const amountMinor = body.amountMinor;
    const currency =
      typeof body.currency === 'string' ? body.currency.trim().toUpperCase() : '';
    if (!Number.isInteger(amountMinor) || amountMinor <= 0 || currency !== 'SEK') {
      send(res, 400, { code: 'INVALID_PAYMENT_INTENT' }, requestId);
      return;
    }
    const intent = {
      id: `pi_${requestId}`,
      status: 'requires_confirmation',
      amountMinor,
      currency: 'SEK',
    };
    paymentIntents.set(intent.id, intent);
    const payload = { code: 'OK', intent: { ...intent } };
    if (key) idempotency.set(key, payload);
    send(res, 200, payload, requestId);
    return;
  }

  if (
    parts[0] === 'api' &&
    parts[1] === 'v1' &&
    parts[2] === 'payments' &&
    parts[3] &&
    parts[4] === 'confirm' &&
    parts.length === 5 &&
    method === 'POST'
  ) {
    const intent = paymentIntents.get(parts[3]);
    if (!intent) {
      send(res, 404, { code: 'PAYMENT_NOT_FOUND' }, requestId);
      return;
    }
    intent.status = 'succeeded';
    send(
      res,
      200,
      { code: 'OK', status: intent.status, intent: { ...intent } },
      requestId,
    );
    return;
  }

  if (
    parts[0] === 'api' &&
    parts[1] === 'v1' &&
    parts[2] === 'payments' &&
    parts[3] &&
    parts.length === 4 &&
    method === 'GET'
  ) {
    const intent = paymentIntents.get(parts[3]);
    if (!intent) {
      send(res, 404, { code: 'PAYMENT_NOT_FOUND' }, requestId);
      return;
    }
    send(
      res,
      200,
      { code: 'OK', status: intent.status, intent: { ...intent } },
      requestId,
    );
    return;
  }

  if (url === '/api/v1/wallet/topup' && method === 'POST') {
    const body = await readBody(req);
    const payload = {
      code: 'OK',
      status: 'succeeded',
      amountMinor: body.amountMinor || 0,
    };
    if (key) idempotency.set(key, payload);
    send(res, 200, payload, requestId);
    return;
  }

  const body = await readBody(req);
  const handled = await safety.handle(req, res, requestId, body);
  if (handled === false) {
    send(res, 404, { code: 'NOT_FOUND', message: 'Unknown route' }, requestId);
  }
});

const port = process.env.PORT || 8787;
server.listen(port, () => console.log(`movera backend mock :${port}`));
