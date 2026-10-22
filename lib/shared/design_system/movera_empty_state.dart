import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MoveraEmptyState extends StatelessWidget {
  const MoveraEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  static const _ink = Color(0xFF1D252C);
  static const _muted = Color(0xFF5C656C);
  static const _soft = Color(0xFFF1F5F7);
  static const _accent = Color(0xFF2D5878);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title. $message',
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 24,
            vertical: compact ? 10 : 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 48 : 64,
                height: compact ? 48 : 64,
                decoration: const BoxDecoration(
                  color: _soft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _accent, size: compact ? 24 : 30),
              ),
              SizedBox(height: compact ? 12 : 18),
              // rider-j8-16: the container label reads title and message once.
              ExcludeSemantics(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: compact ? 15 : 19,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ExcludeSemantics(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: compact ? 12 : 13.5,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                    height: 1.45,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    actionLabel!,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
