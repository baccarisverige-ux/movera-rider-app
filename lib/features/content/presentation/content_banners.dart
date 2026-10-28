import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/content/rider_content.dart';
import 'package:movera_rider/core/content/rider_content_controller.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The rider banners published from the admin's Content page (slots
/// rider-banner-1 … 6, contract v0.10.0 §19), in the rider's language, each
/// with its https image when it has one. Expired ones are hidden. Nothing
/// is drawn when there is none.
class ContentBanners extends StatelessWidget {
  const ContentBanners({super.key, required this.controller});

  final RiderContentController controller;

  static const height = 112.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final banners = controller.banners;
        if (banners.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SizedBox(
            height: height,
            child: ListView.separated(
              key: const Key('content-banners'),
              scrollDirection: Axis.horizontal,
              itemCount: banners.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  ContentBanner(item: banners[i], wide: banners.length == 1),
            ),
          ),
        );
      },
    );
  }
}

class ContentBanner extends StatelessWidget {
  const ContentBanner({super.key, required this.item, this.wide = false});

  final ContentItem item;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final image = item.image;
    return Container(
      key: ValueKey('content-banner-${item.slot}'),
      width: wide ? width - 40 : width * 0.78,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1D252C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.textIn(L10n.code),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      height: 1.3,
                      color: const Color(0xFF2D5878),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (image != null)
            SizedBox(
              width: 96,
              height: double.infinity,
              child: Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
