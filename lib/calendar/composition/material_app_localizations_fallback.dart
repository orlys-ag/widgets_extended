/// The Material and Cupertino localizations a `material_ui` [MaterialApp]
/// gives by default, put in above the composition's Material widgets where
/// the app gives none.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Puts the US English [DefaultMaterialLocalizations] and
/// [DefaultCupertinoLocalizations] above [child] where the [Localizations]
/// above hold no [MaterialLocalizations] or no [CupertinoLocalizations]
/// respectively, whatever their locale, as an app with no `material_ui`
/// [MaterialApp] above does: one on `package:flutter/material.dart`, whose
/// localizations are types apart, a `WidgetsApp` or a `CupertinoApp`.
/// Where the app gives both, it builds [child] alone, so the app's own
/// words stand.
///
/// The [Localizations] it puts in keeps the locale and the delegates of the
/// one above, and the [Directionality] above, which a [Localizations]
/// would otherwise set from its locale. With no [Localizations] above, it
/// puts in one of the US English locale holding the defaults and
/// [DefaultWidgetsLocalizations].
class MaterialAppLocalizationsFallback extends StatelessWidget {
  /// The localizations [child]'s Material widgets need.
  const MaterialAppLocalizationsFallback({super.key, required this.child});

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final missing = <LocalizationsDelegate<Object?>>[
      if (Localizations.of<MaterialLocalizations>(
            context,
            MaterialLocalizations,
          ) ==
          null)
        const _AnyLocaleMaterialDelegate(),
      if (Localizations.of<CupertinoLocalizations>(
            context,
            CupertinoLocalizations,
          ) ==
          null)
        const _AnyLocaleCupertinoDelegate(),
    ];
    if (missing.isEmpty) {
      return child;
    }
    final direction = Directionality.maybeOf(context);
    final kept = direction == null
        ? child
        : Directionality(textDirection: direction, child: child);
    if (Localizations.maybeLocaleOf(context) == null) {
      return Localizations(
        locale: const Locale("en", "US"),
        delegates: <LocalizationsDelegate<Object?>>[
          ...missing,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: kept,
      );
    }
    return Localizations.override(
      context: context,
      delegates: missing,
      child: kept,
    );
  }
}

/// [DefaultMaterialLocalizations.delegate] for every locale, which loads
/// only for English.
final class _AnyLocaleMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _AnyLocaleMaterialDelegate();

  @override
  bool isSupported(Locale locale) {
    return true;
  }

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    return SynchronousFuture<MaterialLocalizations>(
      const DefaultMaterialLocalizations(),
    );
  }

  @override
  bool shouldReload(_AnyLocaleMaterialDelegate old) {
    return false;
  }
}

/// [DefaultCupertinoLocalizations.delegate] for every locale, which loads
/// only for English.
final class _AnyLocaleCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _AnyLocaleCupertinoDelegate();

  @override
  bool isSupported(Locale locale) {
    return true;
  }

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    return SynchronousFuture<CupertinoLocalizations>(
      const DefaultCupertinoLocalizations(),
    );
  }

  @override
  bool shouldReload(_AnyLocaleCupertinoDelegate old) {
    return false;
  }
}
