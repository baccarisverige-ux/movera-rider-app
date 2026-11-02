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

  /// From the admin's `LegalCompany` (Content › Legal): support e-mail and
  /// phone, and the company's name, org. number and address.
  factory SupportDetails.fromLegalCompany(Map<String, String> company) =>
      SupportDetails(
        email: company['supportEmail'] ?? '',
        phone: company['supportPhone'] ?? '',
        company: [
          company['companyName'],
          company['orgNumber'],
          company['address'],
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join('\n'),
      );

  bool get isEmpty =>
      email.trim().isEmpty && phone.trim().isEmpty && company.trim().isEmpty;
}

/// The one place to fill in when the owner sends the details.
const moveraSupportDetails = SupportDetails(email: '', phone: '', company: '');
