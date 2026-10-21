import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:movera_rider/l10n/l10n.dart';

class RideCompletedGiveReview extends StatefulWidget {
  const RideCompletedGiveReview({super.key, this.onRatingChanged});

  final ValueChanged<double>? onRatingChanged;

  @override
  State<RideCompletedGiveReview> createState() =>
      _RideCompletedGiveReviewState();
}

class _RideCompletedGiveReviewState extends State<RideCompletedGiveReview> {
  // Nothing is rated until the rider rates it; a pre-filled score is the
  // app putting words in their mouth.
  double _rating = 0;

  void _rate(double rating) {
    widget.onRatingChanged?.call(rating);
    setState(() => _rating = rating);
  }

  static String _valueLabel(BuildContext context, double rating) => rating < 1
      ? context.l10n.ratingNotRated
      : context.l10n.ratingStarsValue(rating.round());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(color: AppColor.border, height: 0, thickness: 0.3),
        24.height,
        Center(
          child: TextWidget(
            text: context.l10n.howWasTrip,
            color: AppColor.title,
            fontSize: 20,
            fontWeight: fwSemiBold,
          ),
        ),
        1.height,
        // rider-u177: the stars were five unnamed buttons with no value.
        // A screen reader hears one rating slider instead: what it rates,
        // the stars chosen, and swipe up/down to change them.
        Semantics(
          container: true,
          slider: true,
          label: context.l10n.rateYourDriver,
          value: _valueLabel(context, _rating),
          increasedValue: _rating < 5
              ? _valueLabel(context, _rating + 1)
              : null,
          decreasedValue: _rating > 1
              ? _valueLabel(context, _rating - 1)
              : null,
          onIncrease: _rating < 5 ? () => _rate(_rating + 1) : null,
          onDecrease: _rating > 1 ? () => _rate(_rating - 1) : null,
          child: ExcludeSemantics(
            child: Column(
              children: [
                Center(
                  child: TextWidget(
                    text: context.l10n.rateYourDriver,
                    color: AppColor.subtitle,
                    fontSize: 14,
                    fontWeight: fwNormal,
                  ),
                ),
                8.height,
                Center(
                  child: RatingBar.builder(
                    initialRating: _rating,
                    minRating: 1,
                    glow: false,
                    direction: Axis.horizontal,
                    // Q38: whole stars only.
                    allowHalfRating: false,
                    unratedColor: Color(0xff909090),
                    itemCount: 5,
                    itemSize: ResSize.h * 37,
                    itemPadding: EdgeInsets.symmetric(
                      horizontal: ResSize.w * 6,
                    ),
                    itemBuilder: (context, _) =>
                        Icon(Icons.star_rounded, color: Color(0xffF99417)),
                    onRatingUpdate: _rate,
                    updateOnDrag: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        24.height,
        Divider(color: AppColor.border, height: 0, thickness: 0.3),
      ],
    );
  }
}
