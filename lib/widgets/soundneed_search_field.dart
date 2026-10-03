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
        color: const Color(0xFF1D1B27),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Row(
        children: [
          Icon(widget.prefixIcon, color: Colors.white70, size: 21),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              cursorColor: Colors.white,
              keyboardAppearance: Brightness.dark,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: widget.textInputAction,
              maxLines: 1,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
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
