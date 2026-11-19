class CountryCallingCode {
  final String code;
  final String isoCode;
  final String name;
  final String flag;

  const CountryCallingCode({
    required this.code,
    required this.isoCode,
    required this.name,
    required this.flag,
  });

  static const List<CountryCallingCode> supported = [
    CountryCallingCode(code: '+91', isoCode: 'IN', name: 'India', flag: '🇮🇳'),
    CountryCallingCode(code: '+1', isoCode: 'US', name: 'United States', flag: '🇺🇸'),
    CountryCallingCode(code: '+44', isoCode: 'GB', name: 'United Kingdom', flag: '🇬🇧'),
    CountryCallingCode(code: '+49', isoCode: 'EU', name: 'Germany', flag: '🇩🇪'),
    CountryCallingCode(code: '+33', isoCode: 'EU', name: 'France', flag: '🇫🇷'),
    CountryCallingCode(code: '+971', isoCode: 'GLOBAL', name: 'UAE', flag: '🇦🇪'),
    CountryCallingCode(code: '+65', isoCode: 'GLOBAL', name: 'Singapore', flag: '🇸🇬'),
    CountryCallingCode(code: '+61', isoCode: 'GLOBAL', name: 'Australia', flag: '🇦🇺'),
    CountryCallingCode(code: '+81', isoCode: 'GLOBAL', name: 'Japan', flag: '🇯🇵'),
  ];

  static CountryCallingCode get defaultCountry => supported.first; // India +91

  static CountryCallingCode fromCode(String code) {
    return supported.firstWhere(
      (c) => c.code == code,
      orElse: () => defaultCountry,
    );
  }
}

