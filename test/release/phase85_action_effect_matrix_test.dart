import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

enum ActionEffect {
  platformIntent,
  backendMutation,
  durableLocalPersistence,
  navigationOnly,
  localUiOnly,
}

class CertifiedAction {
  const CertifiedAction({
    required this.surface,
    required this.control,
    required this.effects,
    required this.evidence,
    this.enabled = true,
    this.presentationOnly = false,
    this.honestUnavailable = false,
    this.batch7Phase,
  });

  final String surface;
  final String control;
  final Set<ActionEffect> effects;
  final String evidence;
  final bool enabled;

  /// True only for controls whose product purpose is explicitly local
  /// presentation state (sheet motion, selection draft, honest unavailable
  /// explanation, etc.). A control that claims an external effect may never
  /// use this escape hatch.
  final bool presentationOnly;

  /// Disabled/unavailable product actions must say so instead of looking sent,
  /// connected, paid, called, or otherwise completed.
  final bool honestUnavailable;

  final int? batch7Phase;

  String get id => '$surface::$control';
}

const actions = <CertifiedAction>[
  // Home
  CertifiedAction(
    surface: 'home',
    control: 'where_to',
    effects: {ActionEffect.navigationOnly},
    evidence: 'integration_test/ride_flow_test.dart',
  ),
  CertifiedAction(
    surface: 'home',
    control: 'schedule',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/reservations/scheduled_booking_flow_test.dart',
  ),
  CertifiedAction(
    surface: 'home',
    control: 'home_quick_place',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/saved_places/saved_places_honest_state_test.dart',
  ),
  CertifiedAction(
    surface: 'home',
    control: 'work_quick_place',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/saved_places/saved_places_honest_state_test.dart',
  ),
  CertifiedAction(
    surface: 'home',
    control: 'custom_quick_place',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/saved_places/phase82_saved_places_test.dart',
    batch7Phase: 82,
  ),
  CertifiedAction(
    surface: 'home',
    control: 'add_place',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/saved_places/phase82_saved_places_test.dart',
    batch7Phase: 82,
  ),
  CertifiedAction(
    surface: 'home',
    control: 'recenter_map',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/home/location_controller_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'home',
    control: 'toggle_home_sheet',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/home/runtime_location_booking_recovery_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'home',
    control: 'profile_menu',
    effects: {ActionEffect.navigationOnly},
    evidence: 'integration_test/global_uat_flow_test.dart',
  ),
  CertifiedAction(
    surface: 'home',
    control: 'notifications',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/notifications/phase84_notification_tap_test.dart',
    batch7Phase: 84,
  ),

  // Booking / destination / ride selection.
  CertifiedAction(
    surface: 'booking',
    control: 'destination_text_input',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/destination/search_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'booking',
    control: 'destination_result',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/ride/batch3_phase41_booking_authority_test.dart',
  ),
  CertifiedAction(
    surface: 'booking',
    control: 'pickup_map_confirm',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/ride/post_pickup_journey_test.dart',
  ),
  CertifiedAction(
    surface: 'booking',
    control: 'ride_category',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/ride/batch5_phase68_remote_catalog_safety_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'booking',
    control: 'ride_filter',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/ride/batch5_phase68_remote_catalog_safety_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'booking',
    control: 'payment_choice',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/wallet/default_payment_persist_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'booking',
    control: 'driver_note',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/booking/notes_round_trip_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'booking',
    control: 'book_now',
    effects: {ActionEffect.backendMutation, ActionEffect.navigationOnly},
    evidence: 'integration_test/ride_flow_test.dart',
  ),
  CertifiedAction(
    surface: 'booking',
    control: 'book_for_later',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/reservations/scheduled_booking_flow_test.dart',
  ),

  // Finding.
  CertifiedAction(
    surface: 'finding',
    control: 'cancel_search',
    effects: {ActionEffect.backendMutation, ActionEffect.navigationOnly},
    evidence: 'test/journeys/rider_cancel_test.dart',
  ),
  CertifiedAction(
    surface: 'finding',
    control: 'edit_pickup',
    effects: {ActionEffect.backendMutation},
    evidence: 'test/ride/finding_assignment_edit_race_test.dart',
  ),
  CertifiedAction(
    surface: 'finding',
    control: 'raise_offer',
    effects: {ActionEffect.backendMutation},
    evidence: 'test/ride/finding_controller_test.dart',
  ),
  CertifiedAction(
    surface: 'finding',
    control: 'ride_details',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/ride/finding_state_safety_test.dart',
  ),
  CertifiedAction(
    surface: 'finding',
    control: 'sheet_drag',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/ride/waiting_external_terminal_test.dart',
    presentationOnly: true,
  ),

  // Waiting / matched.
  CertifiedAction(
    surface: 'waiting',
    control: 'driver_profile',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/ride/waiting_external_terminal_test.dart',
  ),
  CertifiedAction(
    surface: 'waiting',
    control: 'driver_call_unavailable',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/safety/phase71_real_calling_test.dart',
    presentationOnly: true,
    honestUnavailable: true,
  ),
  CertifiedAction(
    surface: 'waiting',
    control: 'open_safety',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/safety/safety_test.dart',
  ),
  CertifiedAction(
    surface: 'waiting',
    control: 'cancel_ride',
    effects: {ActionEffect.backendMutation, ActionEffect.navigationOnly},
    evidence: 'test/journeys/rider_cancel_test.dart',
  ),
  CertifiedAction(
    surface: 'waiting',
    control: 'ride_details',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/ride/waiting_external_terminal_test.dart',
  ),
  CertifiedAction(
    surface: 'waiting',
    control: 'arrival_acknowledgement',
    effects: {ActionEffect.backendMutation},
    evidence: 'test/ride/post_pickup_journey_test.dart',
  ),
  CertifiedAction(
    surface: 'waiting',
    control: 'sheet_drag',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/ride/waiting_external_terminal_test.dart',
    presentationOnly: true,
  ),

  // In trip.
  CertifiedAction(
    surface: 'in_trip',
    control: 'open_safety',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/safety/safety_test.dart',
  ),
  CertifiedAction(
    surface: 'in_trip',
    control: 'ride_details',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/ride/waiting_external_terminal_test.dart',
  ),
  CertifiedAction(
    surface: 'in_trip',
    control: 'cancel_trip',
    effects: {ActionEffect.backendMutation, ActionEffect.navigationOnly},
    evidence: 'test/journeys/rider_cancel_test.dart',
  ),
  CertifiedAction(
    surface: 'in_trip',
    control: 'sheet_drag',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/ride/waiting_external_terminal_test.dart',
    presentationOnly: true,
  ),
  // Ride check card (RC2–RC5).
  CertifiedAction(
    surface: 'in_trip',
    control: 'ride_check_call_112',
    effects: {ActionEffect.platformIntent, ActionEffect.backendMutation},
    evidence: 'test/safety/ride_check_card_test.dart',
  ),
  CertifiedAction(
    surface: 'in_trip',
    control: 'ride_check_im_ok',
    effects: {
      ActionEffect.backendMutation,
      ActionEffect.durableLocalPersistence,
    },
    evidence: 'test/safety/ride_check_card_test.dart',
  ),
  CertifiedAction(
    surface: 'in_trip',
    control: 'ride_check_red_row',
    effects: {
      ActionEffect.backendMutation,
      ActionEffect.durableLocalPersistence,
    },
    evidence: 'test/safety/ride_check_card_test.dart',
  ),
  CertifiedAction(
    surface: 'in_trip',
    control: 'ride_check_follow_up_answer',
    effects: {
      ActionEffect.backendMutation,
      ActionEffect.durableLocalPersistence,
    },
    evidence: 'test/safety/ride_check_card_test.dart',
  ),
  CertifiedAction(
    surface: 'in_trip',
    control: 'ride_check_record_audio',
    effects: {
      ActionEffect.platformIntent,
      ActionEffect.durableLocalPersistence,
    },
    evidence: 'test/safety/ride_check_card_test.dart',
  ),
  CertifiedAction(
    surface: 'completion',
    control: 'ride_check_dropped_far',
    effects: {
      ActionEffect.backendMutation,
      ActionEffect.durableLocalPersistence,
    },
    evidence: 'test/safety/ride_check_trip_screen_test.dart',
  ),

  // Completion.
  CertifiedAction(
    surface: 'completion',
    control: 'rating_star',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/journeys/book_to_home_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'completion',
    control: 'tip_choice',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/journeys/book_to_home_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'completion',
    control: 'done',
    effects: {
      ActionEffect.backendMutation,
      ActionEffect.durableLocalPersistence,
      ActionEffect.navigationOnly,
    },
    evidence: 'test/journeys/book_to_home_test.dart',
  ),
  CertifiedAction(
    surface: 'completion',
    control: 'back',
    effects: {
      ActionEffect.backendMutation,
      ActionEffect.durableLocalPersistence,
      ActionEffect.navigationOnly,
    },
    evidence: 'test/journeys/book_to_home_test.dart',
  ),

  // Schedule.
  CertifiedAction(
    surface: 'schedule',
    control: 'date_picker',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/scheduled_rides/stockholm_schedule_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'schedule',
    control: 'time_picker',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/scheduled_rides/stockholm_schedule_test.dart',
    presentationOnly: true,
  ),
  CertifiedAction(
    surface: 'schedule',
    control: 'continue',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/scheduled_rides/phase81_schedule_continue_test.dart',
    batch7Phase: 81,
  ),
  CertifiedAction(
    surface: 'schedule',
    control: 'confirm_scheduled_ride',
    effects: {
      ActionEffect.durableLocalPersistence,
      ActionEffect.navigationOnly,
    },
    evidence: 'test/journeys/reservation_journey_test.dart',
  ),
  CertifiedAction(
    surface: 'schedule',
    control: 'edit_scheduled_ride',
    effects: {ActionEffect.durableLocalPersistence},
    evidence: 'test/reservations/reservation_flow_test.dart',
  ),
  CertifiedAction(
    surface: 'schedule',
    control: 'cancel_scheduled_ride',
    effects: {
      ActionEffect.durableLocalPersistence,
      ActionEffect.navigationOnly,
    },
    evidence: 'integration_test/global_uat_flow_test.dart',
  ),

  // Wallet / payment selection.
  CertifiedAction(
    surface: 'wallet',
    control: 'apple_pay_default',
    effects: {ActionEffect.durableLocalPersistence},
    evidence: 'test/wallet/default_payment_persist_test.dart',
  ),
  CertifiedAction(
    surface: 'wallet',
    control: 'google_pay_default',
    effects: {ActionEffect.durableLocalPersistence},
    evidence: 'test/wallet/default_payment_persist_test.dart',
  ),
  CertifiedAction(
    surface: 'wallet',
    control: 'card_unavailable',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/wallet/payment_method_cancel_test.dart',
    presentationOnly: true,
    honestUnavailable: true,
  ),
  CertifiedAction(
    surface: 'wallet',
    control: 'history_row',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/history/ride_history_real_data_test.dart',
  ),

  // Safety.
  CertifiedAction(
    surface: 'safety',
    control: 'emergency_call',
    effects: {ActionEffect.platformIntent},
    evidence: 'test/safety/phase71_real_calling_test.dart',
  ),
  CertifiedAction(
    surface: 'safety',
    control: 'share_trip',
    effects: {ActionEffect.platformIntent},
    evidence: 'test/safety/safety_test.dart',
  ),
  CertifiedAction(
    surface: 'safety',
    control: 'record_audio',
    effects: {
      ActionEffect.platformIntent,
      ActionEffect.durableLocalPersistence,
    },
    evidence: 'test/safety/safety_test.dart',
  ),
  CertifiedAction(
    surface: 'safety',
    control: 'add_emergency_contact',
    effects: {ActionEffect.backendMutation},
    evidence: 'test/safety/safety_test.dart',
  ),
  CertifiedAction(
    surface: 'safety',
    control: 'delete_emergency_contact',
    effects: {ActionEffect.backendMutation},
    evidence: 'test/safety/safety_test.dart',
  ),
  CertifiedAction(
    surface: 'safety',
    control: 'ridecheck_toggle',
    effects: {ActionEffect.backendMutation},
    evidence: 'test/safety/safety_test.dart',
  ),
  CertifiedAction(
    surface: 'safety',
    control: 'pin_verify',
    effects: {ActionEffect.backendMutation},
    evidence: 'test/safety/secure_ride_pin_store_test.dart',
  ),
  CertifiedAction(
    surface: 'safety',
    control: 'tips',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/safety/safety_test.dart',
  ),

  // Profile.
  CertifiedAction(
    surface: 'profile',
    control: 'personal_info',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/profile/account_flow_test.dart',
  ),
  CertifiedAction(
    surface: 'profile',
    control: 'save_personal_info',
    effects: {ActionEffect.durableLocalPersistence},
    evidence: 'integration_test/global_uat_flow_test.dart',
  ),
  CertifiedAction(
    surface: 'profile',
    control: 'security',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/profile/phase74_account_security_test.dart',
  ),
  CertifiedAction(
    surface: 'profile',
    control: 'security_mutation',
    effects: {ActionEffect.backendMutation},
    evidence: 'test/profile/phase74_account_security_test.dart',
  ),
  CertifiedAction(
    surface: 'profile',
    control: 'privacy',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/profile/account_flow_test.dart',
  ),
  CertifiedAction(
    surface: 'profile',
    control: 'refer_share',
    effects: {ActionEffect.platformIntent},
    evidence: 'test/profile/referral_honest_state_test.dart',
  ),
  CertifiedAction(
    surface: 'profile',
    control: 'sign_out',
    effects: {ActionEffect.backendMutation, ActionEffect.navigationOnly},
    evidence: 'test/auth/phase73_auth_ui_test.dart',
  ),

  // Messages.
  CertifiedAction(
    surface: 'messages',
    control: 'open_thread',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/messages/messages_controller_test.dart',
  ),
  CertifiedAction(
    surface: 'messages',
    control: 'compose_draft',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/messages/phase83_chat_honest_state_test.dart',
    presentationOnly: true,
    batch7Phase: 83,
  ),
  CertifiedAction(
    surface: 'messages',
    control: 'send_unavailable',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/messages/phase83_chat_honest_state_test.dart',
    enabled: false,
    presentationOnly: true,
    honestUnavailable: true,
    batch7Phase: 83,
  ),
  CertifiedAction(
    surface: 'messages',
    control: 'back',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/messages/messages_controller_test.dart',
  ),

  // Notifications.
  CertifiedAction(
    surface: 'notifications',
    control: 'ride_notification_tap',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/notifications/phase84_notification_tap_test.dart',
    batch7Phase: 84,
  ),
  CertifiedAction(
    surface: 'notifications',
    control: 'nonride_notification_tap',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/notifications/phase84_notification_tap_test.dart',
    presentationOnly: true,
    batch7Phase: 84,
  ),
  CertifiedAction(
    surface: 'notifications',
    control: 'back',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/notifications/notifications_empty_state_test.dart',
  ),

  // Support.
  CertifiedAction(
    surface: 'support',
    control: 'help_topic',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/support/support_honest_state_test.dart',
  ),
  CertifiedAction(
    surface: 'support',
    control: 'support_message_unavailable',
    effects: {ActionEffect.localUiOnly},
    evidence: 'test/support/support_honest_state_test.dart',
    presentationOnly: true,
    honestUnavailable: true,
  ),
  CertifiedAction(
    surface: 'support',
    control: 'back',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/support/support_honest_state_test.dart',
  ),

  // Saved Places.
  CertifiedAction(
    surface: 'saved_places',
    control: 'add',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/saved_places/phase82_saved_places_test.dart',
    batch7Phase: 82,
  ),
  CertifiedAction(
    surface: 'saved_places',
    control: 'save',
    effects: {
      ActionEffect.durableLocalPersistence,
      ActionEffect.navigationOnly,
    },
    evidence: 'test/saved_places/phase82_saved_places_test.dart',
    batch7Phase: 82,
  ),
  CertifiedAction(
    surface: 'saved_places',
    control: 'edit',
    effects: {ActionEffect.durableLocalPersistence},
    evidence: 'test/saved_places/phase82_saved_places_test.dart',
    batch7Phase: 82,
  ),
  CertifiedAction(
    surface: 'saved_places',
    control: 'delete',
    effects: {ActionEffect.durableLocalPersistence},
    evidence: 'test/saved_places/phase82_saved_places_test.dart',
    batch7Phase: 82,
  ),
  CertifiedAction(
    surface: 'saved_places',
    control: 'choose_location',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/saved_places/saved_places_honest_state_test.dart',
  ),
  CertifiedAction(
    surface: 'saved_places',
    control: 'select_saved_place',
    effects: {ActionEffect.navigationOnly},
    evidence: 'test/saved_places/saved_places_honest_state_test.dart',
  ),
];

void main() {
  const requiredSurfaces = <String>{
    'home',
    'booking',
    'finding',
    'waiting',
    'in_trip',
    'completion',
    'schedule',
    'wallet',
    'safety',
    'profile',
    'messages',
    'notifications',
    'support',
    'saved_places',
  };

  test(
    'Phase 85 action/effect matrix covers every required product surface',
    () {
      final covered = actions.map((action) => action.surface).toSet();
      expect(covered, containsAll(requiredSurfaces));
      expect(requiredSurfaces.difference(covered), isEmpty);
    },
  );

  test(
    'Phase 85 action ids are unique and every classification has evidence',
    () {
      final ids = <String>{};
      for (final action in actions) {
        expect(
          ids.add(action.id),
          isTrue,
          reason: 'Duplicate action: ${action.id}',
        );
        expect(
          action.effects,
          isNotEmpty,
          reason: 'Missing effect: ${action.id}',
        );
        expect(
          File(action.evidence).existsSync(),
          isTrue,
          reason:
              'Missing behavior evidence for ${action.id}: ${action.evidence}',
        );
      }
    },
  );

  test('no enabled product-looking action is certified as local-only', () {
    for (final action in actions.where((action) => action.enabled)) {
      final onlyLocal =
          action.effects.length == 1 &&
          action.effects.contains(ActionEffect.localUiOnly);
      if (onlyLocal) {
        expect(
          action.presentationOnly,
          isTrue,
          reason:
              '${action.id} is enabled and local-only but is not explicitly a presentation control.',
        );
      }
    }
  });

  test('honest unavailable actions never claim a remote effect', () {
    for (final action in actions.where((action) => action.honestUnavailable)) {
      expect(
        action.effects,
        equals({ActionEffect.localUiOnly}),
        reason: '${action.id} must fail closed as local UI only.',
      );
      expect(action.presentationOnly, isTrue);
    }
  });

  test('Batch 7 Phases 81-84 are represented by their real effects', () {
    final byPhase = <int, List<CertifiedAction>>{};
    for (final action in actions) {
      final phase = action.batch7Phase;
      if (phase != null) (byPhase[phase] ??= []).add(action);
    }

    expect(byPhase.keys, containsAll(<int>{81, 82, 83, 84}));

    expect(
      byPhase[81]!.any(
        (action) =>
            action.control == 'continue' &&
            action.effects.contains(ActionEffect.navigationOnly),
      ),
      isTrue,
    );
    expect(
      byPhase[82]!.any(
        (action) =>
            action.control == 'save' &&
            action.effects.contains(ActionEffect.durableLocalPersistence),
      ),
      isTrue,
    );
    expect(
      byPhase[83]!.any(
        (action) =>
            action.control == 'send_unavailable' &&
            action.enabled == false &&
            action.honestUnavailable,
      ),
      isTrue,
    );
    expect(
      byPhase[84]!.any(
        (action) =>
            action.control == 'ride_notification_tap' &&
            action.effects.contains(ActionEffect.navigationOnly),
      ),
      isTrue,
    );
  });
}
