import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'insurance_purchase_screen.dart';
import 'theme_colors.dart';

class PlanDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> plan;

  const PlanDetailsScreen({super.key, required this.plan});

  @override
  State<PlanDetailsScreen> createState() => _PlanDetailsScreenState();
}

class _PlanDetailsScreenState extends State<PlanDetailsScreen> {
  late final Stream<List<Map<String, dynamic>>> _planStream;

  @override
  void initState() {
    super.initState();
    final supabase = Supabase.instance.client;
    _planStream = supabase
        .from('insurance_plans')
        .stream(primaryKey: ['id'])
        .eq('id', widget.plan['id']);
  }

  @override
  Widget build(BuildContext context) {
    const Color brandIndigo = Color(0xFF6366F1);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _planStream,
      builder: (context, snapshot) {
        final data = (snapshot.hasData && snapshot.data!.isNotEmpty)
            ? snapshot.data!.first
            : widget.plan;

        final double price =
            double.tryParse(data['price']?.toString() ?? '0') ?? 0.0;
        final int discount = data['discount'] ?? 0;
        final double discountedPrice = price - (price * (discount / 100));
        final List<dynamic> benefits = data['benefits'] is List
            ? data['benefits']
            : (data['benefits']?.toString().split(',') ??
                ["General Coverage", "Hospital Verified"]);
        final String? iconUrl = data['icon_url']?.toString();
        final bool hasIcon = iconUrl != null && iconUrl.isNotEmpty;
        final String planName = data['name']?.toString() ?? 'Plan';
        final String hospitalName =
            data['hospital_name']?.toString() ?? "Verified Hospital Plan";
        final String description =
            data['description']?.toString() ?? "No description available.";
        final String planType = data['plan_type']?.toString() ?? '';
        final String category = data['category']?.toString() ?? '';

        return Scaffold(
          backgroundColor: const Color(0xFFF8F8FF),
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  // ── Hero Header ──────────────────────────
                  SliverAppBar(
                    expandedHeight: 280,
                    pinned: true,
                    backgroundColor: brandIndigo,
                    elevation: 0,
                    leading: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Background image or gradient
                          hasIcon
                              ? Image.network(
                                  iconUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _gradientBackground(brandIndigo),
                                )
                              : _gradientBackground(brandIndigo),

                          // Overlay gradient
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  brandIndigo.withValues(alpha: 0.3),
                                  brandIndigo.withValues(alpha: 0.9),
                                ],
                              ),
                            ),
                          ),

                          // Plan name + hospital overlaid on header
                          Positioned(
                            bottom: 24,
                            left: 20,
                            right: 20,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Category / type badges
                                if (category.isNotEmpty || planType.isNotEmpty)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if (category.isNotEmpty)
                                        _headerBadge(category),
                                      if (planType.isNotEmpty)
                                        _headerBadge(planType),
                                    ],
                                  ),
                                if (category.isNotEmpty || planType.isNotEmpty)
                                  const SizedBox(height: 10),

                                // FIX: maxLines + ellipsis stops pixel overflow
                                // on long plan names
                                Text(
                                  planName,
                                  style: TextStyle(
                                    color: AppColors.cardBg(context),
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    height: 1.2,
                                    letterSpacing: -0.5,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),

                                // Hospital row — also overflow-safe
                                Row(
                                  children: [
                                    const Icon(Icons.verified_rounded,
                                        color: Colors.white70, size: 14),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        hospitalName,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Content ──────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 140),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Price card
                          _buildPriceCard(
                              brandIndigo, price, discount, discountedPrice),

                          const SizedBox(height: 24),

                          // Description
                          _sectionLabel("About This Plan"),
                          const SizedBox(height: 12),
                          _card(
                            child: Text(
                              description,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                height: 1.7,
                                fontSize: 14.5,
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Benefits
                          _sectionLabel("What's Included"),
                          const SizedBox(height: 16),
                          _card(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Column(
                              children: benefits
                                  .asMap()
                                  .entries
                                  .map((entry) => _buildBenefitItem(
                                        entry.value.toString().trim(),
                                        brandIndigo,
                                        entry.key == benefits.length - 1,
                                      ))
                                  .toList(),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Trust badges
                          _buildTrustRow(brandIndigo),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // ── Bottom bar pinned over scroll ─────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(
                    context, data, brandIndigo, price, discount, discountedPrice),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Reusable card wrapper ─────────────────────────────────
  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ── Section label with indigo left bar ───────────────────
  Widget _sectionLabel(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }

  // ── Gradient fallback header ──────────────────────────────
  Widget _gradientBackground(Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            color.withValues(alpha: 0.75),
            const Color(0xFF818CF8),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.shield_rounded,
          size: 100,
          color: Colors.white.withValues(alpha: 0.15),
        ),
      ),
    );
  }

  // ── Header badge (category / plan_type) ──────────────────
  Widget _headerBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.cardBg(context),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── Price card ────────────────────────────────────────────
  Widget _buildPriceCard(
      Color brandIndigo, double price, int discount, double discountedPrice) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            brandIndigo.withValues(alpha: 0.08),
            brandIndigo.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: brandIndigo.withValues(alpha: 0.15), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  discount > 0 ? "Special Offer" : "Plan Price",
                  style: TextStyle(
                    color: brandIndigo,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                // FIX: Wrap handles price + strikethrough
                // on narrow screens without overflow
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      "Rs. ${discountedPrice.toStringAsFixed(0)}",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: brandIndigo,
                        letterSpacing: -1,
                      ),
                    ),
                    if (discount > 0)
                      Text(
                        "Rs. ${price.toStringAsFixed(0)}",
                        style: TextStyle(
                          fontSize: 16,
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                  ],
                ),
                if (discount > 0)
                  Text(
                    "You save Rs. ${(price - discountedPrice).toStringAsFixed(0)}",
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (discount > 0) ...[
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "-$discount%",
                    style: TextStyle(
                      color: AppColors.cardBg(context),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const Text(
                    "OFF",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Benefit item ──────────────────────────────────────────
  Widget _buildBenefitItem(String title, Color brandIndigo, bool isLast) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: brandIndigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Icon(Icons.check_rounded, size: 16, color: brandIndigo),
              ),
              const SizedBox(width: 14),
              // FIX: Expanded absorbs remaining width — no overflow possible
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF374151),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: const Color(0xFFF1F5F9), indent: 44),
      ],
    );
  }

  // ── Trust row ─────────────────────────────────────────────
  Widget _buildTrustRow(Color brandIndigo) {
    final items = [
      (Icons.security_rounded, "Secure"),
      (Icons.verified_rounded, "Verified"),
      (Icons.support_agent_rounded, "24/7 Support"),
    ];
    return Row(
      children: items.asMap().entries.map((entry) {
        final isLast = entry.key == items.length - 1;
        final item = entry.value;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: isLast ? 0 : 10),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
            ),
            child: Column(
              children: [
                Icon(item.$1, color: brandIndigo, size: 22),
                const SizedBox(height: 6),
                Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Bottom purchase bar ───────────────────────────────────
  Widget _buildBottomBar(
    BuildContext context,
    Map<String, dynamic> data,
    Color brandIndigo,
    double price,
    int discount,
    double discountedPrice,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // FIX: Fixed width + FittedBox auto-shrinks price on small screens
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Total Amount",
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                if (discount > 0)
                  Text(
                    "Rs. ${price.toStringAsFixed(0)}",
                    style: TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: AppColors.textMuted(context),
                      fontSize: 12,
                    ),
                  ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Rs. ${discountedPrice.toStringAsFixed(0)}",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: brandIndigo,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InsurancePurchaseScreen(plan: data),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: brandIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Purchase Now",
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}