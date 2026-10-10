import 'package:flutter/material.dart';

/// Shared search input styled for SoundNeed's dark, rounded interface.
class SoundNeedSearchField extends StatefulWidget {
  const SoundNeedSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.prefixIcon = Icons.search_rounded,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
    this.autofocus = false,
    this.textInputAction = TextInputAction.search,
    this.height = 54,
    this.prominent = true,
    this.accent = const Color(0xFF8B5CF6),
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final bool autofocus;
  final TextInputAction textInputAction;
  final double height;
  final bool prominent;
  final Color accent;

  @override
  State<SoundNeedSearchField> createState() => _SoundNeedSearchFieldState();
}

class _SoundNeedSearchFieldState extends State<SoundNeedSearchField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _focusNode.requestFocus,
    child: Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: widget.prominent
            ? LinearGradient(
                colors: const [Color(0xFF24212E), Color(0xFF17151F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: widget.prominent ? null : const Color(0xFF1D1B27),
        borderRadius: BorderRadius.circular(widget.prominent ? 30 : 20),
        border: Border.all(
          color: _focusNode.hasFocus
              ? widget.accent.withValues(alpha: .62)
              : Colors.white.withValues(alpha: widget.prominent ? .16 : .09),
          width: _focusNode.hasFocus ? 1.35 : 1,
        ),
        boxShadow: widget.prominent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .24),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                if (_focusNode.hasFocus)
                  BoxShadow(
                    color: widget.accent.withValues(alpha: .14),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            widget.prefixIcon,
            color: _focusNode.hasFocus
                ? widget.accent
                : widget.prominent
                ? Colors.white
                : Colors.white70,
            size: widget.prominent ? 23 : 21,
          ),
          SizedBox(width: widget.prominent ? 12 : 11),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              autocorrect: false,
              enableSuggestions: false,
              cursorColor: Colors.white,
              keyboardAppearance: Brightness.dark,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: widget.textInputAction,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.prominent ? 15 : 14,
                fontWeight: widget.prominent
                    ? FontWeight.w500
                    : FontWeight.normal,
                letterSpacing: .1,
                decoration: TextDecoration.none,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                filled: false,
                fillColor: Colors.transparent,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(
                    alpha: widget.prominent ? .64 : .54,
                  ),
                  fontSize: widget.prominent ? 14 : 14,
                  fontWeight: widget.prominent
                      ? FontWeight.w500
                      : FontWeight.normal,
                  letterSpacing: .1,
                  decoration: TextDecoration.none,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (widget.suffix != null) ...[
            const SizedBox(width: 6),
            widget.suffix!,
          ],
        ],
      ),
    ),
  );
}
