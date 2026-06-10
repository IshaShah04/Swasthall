import 'upcoming_booking.dart';

class HomeData {
  final UpcomingBooking? upcomingBooking;
  final int reportCount;
  final int unreadNotificationCount;

  const HomeData({
    this.upcomingBooking,
    required this.reportCount,
    required this.unreadNotificationCount,
  });
}
