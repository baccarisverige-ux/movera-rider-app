import 'package:movera_rider/l10n/l10n.dart';

class RideNotes {
  const RideNotes({
    this.bags = false,
    this.pet = false,
    this.baby = false,
    this.child = false,
    this.manyBags = false,
  });

  final bool bags;
  final bool pet;
  final bool baby;
  final bool child;

  /// With [bags]: three or more bags (asked on Set pickup as No / 1–2 / 3+).
  final bool manyBags;

  static const empty = RideNotes();

  bool get isEmpty => !bags && !pet && !baby && !child;

  /// Bags as the rider chose them on Set pickup: 0 = none, 1 = 1–2, 2 = 3+.
  int get bagLevel => !bags ? 0 : (manyBags ? 2 : 1);

  RideNotes withBagLevel(int level) => RideNotes(
    bags: level > 0,
    manyBags: level > 1,
    pet: pet,
    baby: baby,
    child: child,
  );

  List<String> get selected {
    return [
      if (bags) manyBags ? 'Bags 3+' : 'Bags',
      if (pet) 'Pet',
      if (baby) 'Baby',
      if (child) 'Child',
    ];
  }

  /// A [selected] label ('Bags 3+', 'Pet', ...) in the app language; the
  /// English label stays what is saved and sent.
  static String labelFor(String label) => switch (label) {
    'Bags 3+' => '${L10n.current.notesBags} 3+',
    'Bags' => L10n.current.notesBags,
    'Pet' => L10n.current.notesPet,
    'Baby' => L10n.current.notesBaby,
    'Child' => L10n.current.notesChild,
    _ => label,
  };

  /// A saved ride note ("Leave at the gate · Bags · Pet") with its
  /// [selected] labels in the app language; the rider's own words stay.
  static String displayNote(String note) => [
    for (final part in note.split(' · '))
      [for (final item in part.split(', ')) labelFor(item)].join(', '),
  ].join(' · ');

  RideNotes copyWith({bool? bags, bool? pet, bool? baby, bool? child}) {
    return RideNotes(
      bags: bags ?? this.bags,
      manyBags: (bags ?? this.bags) && manyBags,
      pet: pet ?? this.pet,
      baby: baby ?? this.baby,
      child: child ?? this.child,
    );
  }

  RideNotes toggle(String key) {
    switch (key) {
      case 'bags':
        return copyWith(bags: !bags);
      case 'pet':
        return copyWith(pet: !pet);
      case 'baby':
        return copyWith(baby: !baby);
      case 'child':
        return copyWith(child: !child);
      default:
        return this;
    }
  }

  Map<String, dynamic> toJson() => {
    'bags': bags,
    if (bags) 'bagsCount': manyBags ? '3+' : '1-2',
    'pet': pet,
    'baby': baby,
    'child': child,
  };

  factory RideNotes.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return RideNotes(
      bags: json['bags'] == true,
      manyBags: json['bags'] == true && json['bagsCount'] == '3+',
      pet: json['pet'] == true,
      baby: json['baby'] == true,
      child: json['child'] == true,
    );
  }
}
