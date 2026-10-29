/// Movera's support contact, shown under "Need help?" before sign-in
/// (owner 2026-10-29: "Add help and add email and phone and details for
/// company, we add missing info later"). The values are built into the app;
/// the owner sends them later, so fill them in here. While all are empty
/// the box says "Contact details coming soon".
class SupportDetails {
  const SupportDetails({this.email = '', this.phone = '', this.company = ''});

  /// Support e-mail, e.g. "support@example.com".
  final String email;

  /// Support phone in international form, e.g. "+46 8 123 45 67".
  final String phone;

  /// Company details as they should read: name, org. number, address.
  final String company;

  bool get isEmpty =>
      email.trim().isEmpty && phone.trim().isEmpty && company.trim().isEmpty;
}

/// The one place to fill in when the owner sends the details.
const moveraSupportDetails = SupportDetails(email: '', phone: '', company: '');
