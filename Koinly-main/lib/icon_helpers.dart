import 'package:flutter/material.dart';

import 'app_config.dart';
import 'models.dart';

IconData iconFor(String name) {
  switch (name) {
    case 'wallet': return Icons.account_balance_wallet_rounded;
    case 'credit_card': return Icons.credit_card_rounded;
    case 'bank': return Icons.account_balance_rounded;
    case 'savings': return Icons.savings_rounded;
    case 'cash': return Icons.payments_rounded;
    case 'atm': return Icons.atm_rounded;
    case 'receipt': return Icons.receipt_long_rounded;
    case 'calculator': return Icons.calculate_rounded;
    case 'apparel': return Icons.checkroom_rounded;
    case 'shopping_bag': return Icons.shopping_bag_rounded;
    case 'cart': return Icons.shopping_cart_rounded;
    case 'store': return Icons.storefront_rounded;
    case 'food': return Icons.restaurant_rounded;
    case 'groceries': return Icons.local_grocery_store_rounded;
    case 'coffee': return Icons.local_cafe_rounded;
    case 'fastfood': return Icons.fastfood_rounded;
    case 'health': return Icons.health_and_safety_rounded;
    case 'hospital': return Icons.local_hospital_rounded;
    case 'medicine': return Icons.medication_rounded;
    case 'favorite': return Icons.favorite_rounded;
    case 'leisure': return Icons.pool_rounded;
    case 'games': return Icons.sports_esports_rounded;
    case 'movie': return Icons.movie_rounded;
    case 'music': return Icons.music_note_rounded;
    case 'sports': return Icons.sports_soccer_rounded;
    case 'fitness': return Icons.fitness_center_rounded;
    case 'book': return Icons.menu_book_rounded;
    case 'school': return Icons.school_rounded;
    case 'car': return Icons.directions_car_rounded;
    case 'bus': return Icons.directions_bus_rounded;
    case 'train': return Icons.train_rounded;
    case 'flight': return Icons.flight_rounded;
    case 'anime': return Icons.auto_awesome_rounded;
    case 'manga': return Icons.auto_stories_rounded;
    case 'collectibles': return Icons.toys_rounded;
    case 'headphones': return Icons.headphones_rounded;
    case 'keyboard': return Icons.keyboard_rounded;
    case 'laptop': return Icons.laptop_mac_rounded;
    case 'monitor': return Icons.desktop_windows_rounded;
    case 'mic': return Icons.mic_rounded;
    case 'video': return Icons.videocam_rounded;
    case 'art': return Icons.brush_rounded;
    case 'subscription': return Icons.subscriptions_rounded;
    case 'fuel': return Icons.local_gas_station_rounded;
    case 'home': return Icons.home_rounded;
    case 'house': return Icons.house_rounded;
    case 'apartment': return Icons.apartment_rounded;
    case 'utilities': return Icons.lightbulb_rounded;
    case 'water': return Icons.water_drop_rounded;
    case 'wifi': return Icons.wifi_rounded;
    case 'phone': return Icons.phone_android_rounded;
    case 'bolt': return Icons.bolt_rounded;
    case 'gift': return Icons.card_giftcard_rounded;
    case 'celebration': return Icons.celebration_rounded;
    case 'travel': return Icons.beach_access_rounded;
    case 'pets': return Icons.pets_rounded;
    case 'baby': return Icons.child_care_rounded;
    case 'beauty': return Icons.face_retouching_natural_rounded;
    case 'salary': return Icons.payments_rounded;
    case 'work': return Icons.work_rounded;
    case 'business': return Icons.business_center_rounded;
    case 'investment': return Icons.trending_up_rounded;
    case 'money': return Icons.attach_money_rounded;
    case 'exchange': return Icons.currency_exchange_rounded;
    case 'coupon': return Icons.confirmation_number_rounded;
    case 'donation': return Icons.volunteer_activism_rounded;
    case 'security': return Icons.security_rounded;
    case 'insurance': return Icons.policy_rounded;
    case 'tools': return Icons.build_rounded;
    case 'construction': return Icons.construction_rounded;
    case 'cleaning': return Icons.cleaning_services_rounded;
    case 'laundry': return Icons.local_laundry_service_rounded;
    case 'parking': return Icons.local_parking_rounded;
    case 'calendar': return Icons.calendar_month_rounded;
    case 'time': return Icons.schedule_rounded;
    case 'schedule': return Icons.schedule_rounded;
    case 'camera_alt': return Icons.photo_camera_rounded;
    case 'sports_esports': return Icons.sports_esports_rounded;
    case 'filter': return Icons.filter_alt_rounded;
    case 'today': return Icons.today_rounded;
    case 'week': return Icons.view_week_rounded;
    case 'month': return Icons.calendar_month_rounded;
    case 'year': return Icons.event_note_rounded;
    case 'all_time': return Icons.all_inclusive_rounded;
    case 'custom_range': return Icons.date_range_rounded;
    case 'theme_system': return Icons.devices_rounded;
    case 'theme_light': return Icons.light_mode_rounded;
    case 'theme_dark': return Icons.dark_mode_rounded;
    case 'theme_battery': return Icons.battery_saver_rounded;
    case 'flag': return Icons.flag_rounded;
    case 'profile': return Icons.account_circle_rounded;
    case 'check': return Icons.verified_rounded;
    case 'warning': return Icons.warning_amber_rounded;
    case 'reminder': return Icons.notifications_active_rounded;
    case 'download': return Icons.system_update_alt_rounded;
    default: return Icons.category_rounded;
  }
}

bool isImageIcon(String name) => name == 'origami_bird';

String imageIconAsset(String name) {
  switch (name) {
    case 'origami_bird':
      return 'assets/icons/origami_bird.png';
    default:
      return '';
  }
}

Widget iconGlyph(
  BuildContext context,
  String icon, {
  required Color color,
  required double size,
  Color? imageBackground,
}) {
  if (isImageIcon(icon)) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .10),
      decoration: imageBackground == null || icon == 'origami_bird'
          ? null
          : BoxDecoration(
              color: imageBackground,
              borderRadius: BorderRadius.circular(size * .28),
            ),
      child: Image.asset(
        imageIconAsset(icon),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
  return Icon(iconFor(icon), color: color, size: size);
}

Widget iconBubble(BuildContext context, String icon, String color, {double size = 44}) {
  final c = colorFromHex(color, fallback: Theme.of(context).colorScheme.primary);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: c.withOpacity(dark ? .20 : .16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          c.withOpacity(dark ? .26 : .18),
          c.withOpacity(dark ? .10 : .08),
        ],
      ),
      borderRadius: BorderRadius.circular(size * .32),
      border: Border.all(color: c.withOpacity(dark ? .34 : .25), width: 1),
      boxShadow: kIsDesktopApp ? null : [BoxShadow(color: c.withOpacity(.15), blurRadius: 14, offset: const Offset(0, 6))],
    ),
    child: Center(
      child: iconGlyph(
        context,
        icon,
        color: c,
        size: size * .56,
        imageBackground: Colors.white.withOpacity(.84),
      ),
    ),
  );
}
