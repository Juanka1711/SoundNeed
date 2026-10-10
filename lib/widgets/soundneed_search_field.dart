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
    this.prominent = false,
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

  @override
  State<SoundNeedSearchField> createState() => _SoundNeedSearchFieldState();
}

class _SoundNeedSearchFieldState extends State<SoundNeedSearchField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
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
            ? const LinearGradient(
                colors: [Color(0xFF292633), Color(0xFF1C1B24)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: widget.prominent ? null : const Color(0xFF1D1B27),
        borderRadius: BorderRadius.circular(widget.prominent ? 22 : 20),
        border: Border.all(
          color: Colors.white.withValues(alpha: widget.prominent ? .22 : .09),
          width: widget.prominent ? 1.2 : 1,
        ),
        boxShadow: widget.prominent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .28),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: .035),
                  blurRadius: 1,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            widget.prefixIcon,
            color: widget.prominent ? Colors.white : Colors.white70,
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
                fontWeight: widget.prominent ? FontWeight.w500 : FontWeight.normal,
                decoration: TextDecoration.none,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: widget.prominent ? .64 : .54),
                  fontSize: widget.prominent ? 14 : 14,
                  fontWeight: widget.prominent ? FontWeight.w500 : FontWeight.normal,
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
