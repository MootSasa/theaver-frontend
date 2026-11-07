import 'package:flutter/material.dart';

class FiltersWidget extends StatelessWidget {
  final String currentFilter;
  final ValueChanged<String> onFilterSelected;

  const FiltersWidget({
    Key? key,
    required this.currentFilter,
    required this.onFilterSelected,
  }) : super(key: key);

  static const List<String> _filters = [
    'All',
    'Personal',
    'Groups',
    'Channels',
    'Communities',
    'Folders',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40.0, // Fixed height for the filter list
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final bool isSelected = filter == currentFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (_) => onFilterSelected(filter),
              selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).textTheme.bodySmall?.color,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
                side: BorderSide(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade300,
                ),
              ),
              pressElevation: 0,
            ),
          );
        },
      ),
    );
  }
}