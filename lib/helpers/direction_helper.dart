import 'package:flutter/widgets.dart';

/// اتجاه التخطيط العام للتطبيق.
///
/// يبقى LTR دائماً حتى عند اختيار اللغة العربية، حتى لا تنعكس أماكن
/// الأزرار والبطاقات والعناصر. النص العربي نفسه يبقى يُعرض بشكل صحيح
/// داخل التخطيط.
TextDirection appTextDirection(Locale locale) => TextDirection.ltr;