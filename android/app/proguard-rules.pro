# flutter_stripe 11.5.0, README "Requirements >
# Android" step 7: the Stripe SDK names its optional push-provisioning
# classes, which are not in the app. Without these lines R8 stops the release
# build with "Missing classes detected while running R8".
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivity$g
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Args
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Error
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningEphemeralKeyProvider
