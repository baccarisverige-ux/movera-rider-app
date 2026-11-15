package com.movera.rider;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.content.Context;
import android.location.Location;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.graphics.Rect;
import android.os.SystemClock;
import android.system.Os;
import android.util.Log;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import dev.flutter.plugins.integration_test.FlutterTestRunner;
import java.io.File;
import java.io.FileInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Random;
import org.junit.Rule;
import org.junit.runner.RunWith;

/**
 * G31 rider (owner 2026-11-12, "then the RIDER app on phone (driver via API)
 * with the same checks"): runs the rider trip suite in integration_test/
 * (Firebase Test Lab, {@code --type instrumentation}). A copy of the driver
 * app's runner (Movera-driver-app android/app/src/androidTest, merged #570)
 * with the rider's run-time names.
 *
 * <p>Sign-in values come only at run time, as instrumentation arguments
 * ({@code gcloud ... --environment-variables}, mirrored to {@code am instrument -e}).
 * They are handed to the Dart test as process environment variables before the
 * activity (and so the Dart VM) starts. Nothing is built into an APK, and no value
 * is ever logged.
 *
 * <p>The phone's position is the app's real location stack (geolocator), fed
 * with mock fixes at the rider's pickup point because a Test Lab phone in a
 * rack has no GPS signal. The rider does not move during the run (the driver
 * is played over HTTP); the target file is kept so a later run can move it.
 */
@RunWith(FlutterTestRunner.class)
public class MainActivityTest {
  private static final String TAG = "MoveraTL";

  /** Instrumentation argument -> environment variable read by the Dart test. */
  private static final String[][] ARGS = {
    {"movera_tl_phone", "MOVERA_TL_PHONE"},
    {"movera_tl_code", "MOVERA_TL_CODE"},
    // The driver played over HTTP, and which scenario (live | scheduled).
    {"movera_tl_peer_phone", "MOVERA_TL_PEER_PHONE"},
    {"movera_tl_scenario", "MOVERA_TL_SCENARIO"},
    {"movera_tl_lat", "MOVERA_TL_LAT"},
    {"movera_tl_lng", "MOVERA_TL_LNG"},
    {"movera_tl_dropoff_query", "MOVERA_TL_DROPOFF_QUERY"},
    {"movera_tl_shots", "MOVERA_TL_SHOTS"},
  };

  /**
   * The rider's pickup: central Stockholm (zone Z001) unless the run names
   * another point; the same default as integration_test/staging/rider_session.dart.
   */
  private static final double DEFAULT_LAT = 59.3326;

  private static final double DEFAULT_LNG = 18.0649;

  static {
    prepare();
  }

  @Rule
  public ActivityTestRule<MainActivity> rule =
      new ActivityTestRule<>(MainActivity.class, true, false);

  private static void prepare() {
    Bundle args;
    Instrumentation instrumentation;
    try {
      instrumentation = InstrumentationRegistry.getInstrumentation();
      args = InstrumentationRegistry.getArguments();
    } catch (IllegalStateException e) {
      Log.w(TAG, "no instrumentation registry: " + e.getClass().getSimpleName());
      return;
    }
    int handed = 0;
    for (String[] pair : ARGS) {
      String value = args.getString(pair[0]);
      if (value == null || value.isEmpty()) continue;
      try {
        Os.setenv(pair[1], value, true);
        handed++;
      } catch (Exception e) {
        Log.w(TAG, "could not hand over " + pair[0] + ": " + e.getClass().getSimpleName());
      }
    }
    // Names only, never values.
    Log.i(TAG, "run-time values handed to the test: " + handed);

    Context app = instrumentation.getTargetContext();
    File out = app.getExternalFilesDir("tl");
    if (out != null) {
      try {
        Os.setenv("MOVERA_TL_OUT", out.getAbsolutePath(), true);
      } catch (Exception e) {
        Log.w(TAG, "no output folder: " + e.getClass().getSimpleName());
      }
    }

    if (!"0".equals(args.getString("movera_tl_mock_location"))) {
      targetLat = parse(args.getString("movera_tl_lat"), DEFAULT_LAT);
      targetLng = parse(args.getString("movera_tl_lng"), DEFAULT_LNG);
      // The Dart test moves the mock position at run time by writing
      // "lat,lng" into this file (app-private; coordinates only).
      File target = new File(app.getFilesDir(), "tl-mock-target");
      if (target.exists() && !target.delete()) {
        Log.w(TAG, "old mock target not removed");
      }
      targetFile = target;
      try {
        Os.setenv("MOVERA_TL_MOCK_FILE", target.getAbsolutePath(), true);
      } catch (Exception e) {
        Log.w(TAG, "no mock target file: " + e.getClass().getSimpleName());
      }
      startMockLocation(instrumentation, app);
    }
  }

  private static double parse(String value, double fallback) {
    if (value == null) return fallback;
    try {
      return Double.parseDouble(value);
    } catch (NumberFormatException e) {
      return fallback;
    }
  }

  /** Runs a shell command as the shell user; returns its output (trimmed, never null). */
  private static String shell(Instrumentation instrumentation, String command) {
    ParcelFileDescriptor pfd = instrumentation.getUiAutomation().executeShellCommand(command);
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    try (InputStream in = new FileInputStream(pfd.getFileDescriptor())) {
      byte[] buffer = new byte[256];
      int n;
      while ((n = in.read(buffer)) != -1) {
        // The command ends when its output is read.
        if (out.size() < 4096) out.write(buffer, 0, n);
      }
    } catch (IOException e) {
      Log.w(TAG, "shell: " + e.getClass().getSimpleName());
    } finally {
      try {
        pfd.close();
      } catch (IOException ignored) {
        // Closed already.
      }
    }
    return new String(out.toByteArray(), StandardCharsets.UTF_8).trim();
  }

  /**
   * Device location on, in high-accuracy mode, with Google location accuracy
   * (network location consent) on, BEFORE the app starts.
   *
   * <p>Test Lab runs 43408227182, 43428481576 and 43737785526: the phone had
   * Google location accuracy off, so Play services answered the app's
   * high-accuracy location request with its own dialog
   * ({@code location.settings.CHECK_SETTINGS}, LocationSettingsCheckerActivity).
   * Nobody answered it, no fix reached the app (the mock fixes were injected
   * but never delivered), the pickup stayed the fallback point and Confirm
   * stayed disabled (D-002), so BOOK never posted /trips. This sets the
   * phone up the way a rider's phone with location on is; the app is not
   * changed. {@link #watchLocationDialog} answers the dialog if it still shows.
   * The settings values below are device switches, not personal data; logged
   * so a run shows which path was taken.
   */
  private static void prepareDeviceLocation(Instrumentation instrumentation) {
    String[] commands = {
      "cmd location set-location-enabled true",
      // 3 = LOCATION_MODE_HIGH_ACCURACY (GPS + network).
      "settings put secure location_mode 3",
      // Google location accuracy ("NLP consent" read by Play services'
      // LocationSettings); both tables, as GMS versions differ.
      "settings put secure network_location_opt_in 1",
      "settings put global network_location_opt_in 1",
      "settings put global assisted_gps_enabled 1",
    };
    for (String command : commands) {
      String out = shell(instrumentation, command);
      if (!out.isEmpty()) Log.w(TAG, "location setup: '" + command + "' said: " + out);
    }
    Log.i(
        TAG,
        "location setup: enabled="
            + shell(instrumentation, "cmd location is-location-enabled")
            + " location_mode="
            + shell(instrumentation, "settings get secure location_mode")
            + " nlp_opt_in(secure)="
            + shell(instrumentation, "settings get secure network_location_opt_in")
            + " nlp_opt_in(global)="
            + shell(instrumentation, "settings get global network_location_opt_in")
            + " assisted_gps="
            + shell(instrumentation, "settings get global assisted_gps_enabled"));
  }

  private static final String GMS = "com.google.android.gms";

  /** The accepting button of Play services' location dialog (never "No thanks"). */
  private static final String[] ACCEPT = {"turn on", "ok", "agree", "accept", "yes"};

  /**
   * Fallback for {@link #prepareDeviceLocation}: if Play services' location
   * dialog shows anyway, taps its accepting button (as a rider would) and logs
   * it ("location dialog answered"). Polls every 0.5 s for the whole run.
   */
  private static void watchLocationDialog(final Instrumentation instrumentation) {
    Thread watcher =
        new Thread(
            () -> {
              UiAutomation ui;
              try {
                ui = instrumentation.getUiAutomation();
                AccessibilityServiceInfo info = ui.getServiceInfo();
                if (info != null) {
                  info.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
                  ui.setServiceInfo(info);
                }
              } catch (RuntimeException e) {
                Log.w(TAG, "location dialog watcher off: " + e.getClass().getSimpleName());
                return;
              }
              Log.i(TAG, "location dialog watcher on");
              int answered = 0;
              int polls = 0;
              long lastSeenLog = 0;
              while (true) {
                try {
                  for (AccessibilityNodeInfo root : roots(ui)) {
                    if (root == null || !GMS.equals(String.valueOf(root.getPackageName()))) {
                      continue;
                    }
                    AccessibilityNodeInfo button = acceptButton(root);
                    if (button == null) {
                      long now = SystemClock.elapsedRealtime();
                      if (now - lastSeenLog > 5000) {
                        lastSeenLog = now;
                        Log.i(TAG, "location dialog: Play services window, no accept button yet: "
                            + texts(root));
                      }
                      continue;
                    }
                    String label = String.valueOf(button.getText());
                    AccessibilityNodeInfo target = clickable(button);
                    boolean clicked = target.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                    String how = "click";
                    if (!clicked) {
                      Rect r = new Rect();
                      target.getBoundsInScreen(r);
                      if (r.isEmpty()) {
                        how = "none (button gone)";
                      } else {
                        shell(instrumentation, "input tap " + r.centerX() + " " + r.centerY());
                        how = "input tap";
                      }
                    }
                    answered++;
                    Log.i(TAG, "location dialog answered: tapped '" + label + "' (" + how + "), "
                        + answered + " so far");
                    SystemClock.sleep(1500);
                    // One answer per poll: the same window is in roots() twice.
                    break;
                  }
                } catch (RuntimeException e) {
                  // A window went away while read; the next poll reads again.
                }
                polls++;
                if (polls == 120 && answered == 0) {
                  Log.i(TAG, "location dialog: none in the first 60 s (set-up path)");
                }
                SystemClock.sleep(500);
              }
            },
            "movera-tl-location-dialog");
    watcher.setDaemon(true);
    watcher.start();
  }

  private static List<AccessibilityNodeInfo> roots(UiAutomation ui) {
    List<AccessibilityNodeInfo> roots = new ArrayList<>();
    AccessibilityNodeInfo active = ui.getRootInActiveWindow();
    if (active != null) roots.add(active);
    List<AccessibilityWindowInfo> windows = ui.getWindows();
    if (windows != null) {
      for (AccessibilityWindowInfo window : windows) {
        AccessibilityNodeInfo root = window.getRoot();
        if (root != null) roots.add(root);
      }
    }
    return roots;
  }

  /** The node whose text is an accepting word ("Turn on", "OK", ...), or null. */
  private static AccessibilityNodeInfo acceptButton(AccessibilityNodeInfo node) {
    if (node == null) return null;
    CharSequence text = node.getText();
    if (text != null) {
      String t = text.toString().trim().toLowerCase(Locale.ROOT);
      for (String word : ACCEPT) {
        if (t.equals(word)) return node;
      }
    }
    for (int i = 0; i < node.getChildCount(); i++) {
      AccessibilityNodeInfo found = acceptButton(node.getChild(i));
      if (found != null) return found;
    }
    return null;
  }

  /** The node itself when clickable, else its nearest clickable parent (3 up at most). */
  private static AccessibilityNodeInfo clickable(AccessibilityNodeInfo node) {
    AccessibilityNodeInfo target = node;
    for (int up = 0; target != null && !target.isClickable() && up < 3; up++) {
      target = target.getParent();
    }
    return target != null && target.isClickable() ? target : node;
  }

  /** The window's visible texts (Play services' own UI text, no app data). */
  private static String texts(AccessibilityNodeInfo node) {
    StringBuilder out = new StringBuilder();
    collect(node, out, 0);
    return out.toString();
  }

  private static void collect(AccessibilityNodeInfo node, StringBuilder out, int depth) {
    if (node == null || depth > 30 || out.length() > 300) return;
    if (node.getText() != null) out.append('[').append(node.getText()).append(']');
    for (int i = 0; i < node.getChildCount(); i++) collect(node.getChild(i), out, depth + 1);
  }

  // Where the mock fixes go now; moved by the Dart test through targetFile.
  // No initializers: prepare() runs from the static block above, before
  // field initializers further down, and an initializer here would reset
  // what it set.
  private static volatile double targetLat;

  private static volatile double targetLng;

  private static File targetFile;

  private static long targetStamp;

  /** Reads a new "lat,lng" from [targetFile] when it changed; bad text is ignored. */
  private static void readTarget() {
    File file = targetFile;
    if (file == null || !file.exists()) return;
    long stamp = file.lastModified() ^ file.length();
    if (stamp == targetStamp) return;
    targetStamp = stamp;
    byte[] buffer = new byte[64];
    int n;
    try (InputStream in = new FileInputStream(file)) {
      n = in.read(buffer);
    } catch (IOException e) {
      return;
    }
    if (n <= 0) return;
    String[] parts = new String(buffer, 0, n, StandardCharsets.US_ASCII)
        .trim().split(",");
    if (parts.length != 2) return;
    double lat = parse(parts[0], Double.NaN);
    double lng = parse(parts[1], Double.NaN);
    if (Double.isNaN(lat) || Double.isNaN(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return;
    }
    targetLat = lat;
    targetLng = lng;
    // Coordinates are not personal data; logged so a run shows the moves.
    Log.i(TAG, "mock target moved");
  }

  private static void startMockLocation(Instrumentation instrumentation, Context app) {
    prepareDeviceLocation(instrumentation);
    watchLocationDialog(instrumentation);
    shell(instrumentation, "appops set " + app.getPackageName() + " android:mock_location allow");
    final LocationManager manager =
        (LocationManager) app.getSystemService(Context.LOCATION_SERVICE);
    final List<String> providers = new ArrayList<>();
    List<String> wanted = new ArrayList<>();
    wanted.add(LocationManager.GPS_PROVIDER);
    wanted.add(LocationManager.NETWORK_PROVIDER);
    if (Build.VERSION.SDK_INT >= 31) wanted.add("fused");
    for (String provider : wanted) {
      try {
        manager.addTestProvider(
            provider, false, false, false, false, true, true, true, /* power low */ 1,
            /* accuracy fine */ 1);
        manager.setTestProviderEnabled(provider, true);
        providers.add(provider);
      } catch (RuntimeException e) {
        Log.w(TAG, "mock provider " + provider + ": " + e.getClass().getSimpleName());
      }
    }
    final Object fused = fusedClient(app);
    Log.i(TAG, "mock location providers=" + providers + " fused=" + (fused != null));
    Thread feeder =
        new Thread(
            () -> {
              while (true) {
                readTarget();
                final double lat = targetLat;
                final double lng = targetLng;
                for (String provider : providers) {
                  try {
                    manager.setTestProviderLocation(provider, fix(provider, lat, lng));
                  } catch (RuntimeException e) {
                    // Provider gone (test ending).
                  }
                }
                if (fused != null) {
                  try {
                    Method set =
                        Class.forName(FUSED_CLIENT).getMethod("setMockLocation", Location.class);
                    set.invoke(fused, fix("fused", lat, lng));
                  } catch (Exception e) {
                    // Play services refused one fix; the next second tries again.
                  }
                }
                round++;
                SystemClock.sleep(1000);
              }
            },
            "movera-tl-mock-location");
    feeder.setDaemon(true);
    feeder.start();
  }

  private static final String FUSED_CLIENT =
      "com.google.android.gms.location.FusedLocationProviderClient";

  /** Google Play services' fused provider in mock mode, without a compile dependency. */
  private static Object fusedClient(Context app) {
    try {
      Class<?> services = Class.forName("com.google.android.gms.location.LocationServices");
      Object client =
          services.getMethod("getFusedLocationProviderClient", Context.class).invoke(null, app);
      // Look the methods up on the public interface: the implementation class
      // may not be public, and invoking through it would throw
      // IllegalAccessException (fused mocking silently off).
      Class.forName(FUSED_CLIENT).getMethod("setMockMode", boolean.class).invoke(client, true);
      return client;
    } catch (Exception e) {
      Log.w(TAG, "fused mock: " + e.getClass().getSimpleName());
      return null;
    }
  }

  /** About 10 m in degrees of latitude (1 degree is about 111 km). */
  private static final double JITTER_DEG = 10.0 / 111_000.0;

  private static final Random JITTER = new Random();

  /** Feeder rounds so far (one per second); picks the jitter side. */
  private static volatile int round = 0;

  private static Location fix(String provider, double lat, double lng) {
    Location location = new Location(provider);
    // +/-10 m jitter, north and south of the point in turn (5-10 m each
    // way, so two rounds are >= 10 m apart): the app's 8 m distance filter
    // sees movement, and a G24 FAIL cannot come from a stationary mock.
    double side = (round % 2 == 0) ? 1 : -1;
    location.setLatitude(lat + side * (0.5 + 0.5 * JITTER.nextDouble()) * JITTER_DEG);
    location.setLongitude(
        lng + (JITTER.nextDouble() * 2 - 1) * JITTER_DEG / Math.cos(Math.toRadians(lat)));
    location.setAccuracy(5f);
    location.setAltitude(20);
    location.setSpeed(0f);
    location.setBearing(0f);
    location.setTime(System.currentTimeMillis());
    location.setElapsedRealtimeNanos(SystemClock.elapsedRealtimeNanos());
    if (Build.VERSION.SDK_INT >= 26) {
      location.setVerticalAccuracyMeters(5f);
      location.setSpeedAccuracyMetersPerSecond(1f);
      location.setBearingAccuracyDegrees(10f);
    }
    return location;
  }
}
