import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../services/location/location_service.dart';
import '../../../theme/app_spacing.dart';

/// Interactive Map and Location Picker widget.
/// Provides place/address search, pan/pinch-zoom/tap real OpenStreetMap selection,
/// and optional current location lookup with Geolocator GPS.
class MapLocationPicker extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialPlaceName;
  final String? initialAddress;
  final ValueChanged<LocationSearchResult> onLocationSelected;
  final LocationService? locationService;

  const MapLocationPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialPlaceName,
    this.initialAddress,
    required this.onLocationSelected,
    this.locationService,
  });

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  late final LocationService _locationService;
  late final MapController _mapController;
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isSearching = false;
  List<LocationSearchResult> _searchResults = [];

  // Active coordinates
  late double _mapCenterLat;
  late double _mapCenterLng;
  int _zoom = 14;

  String? _selectedPlaceName;
  String? _selectedAddress;
  bool _hasSelection = false;
  bool _isReverseGeocoding = false;
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    _locationService = widget.locationService ?? LocationService();
    _mapController = MapController();

    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _mapCenterLat = widget.initialLatitude!;
      _mapCenterLng = widget.initialLongitude!;
      _selectedPlaceName = widget.initialPlaceName;
      _selectedAddress = widget.initialAddress;
      _hasSelection = true;
    } else {
      // Default initial viewport (neutral center)
      _mapCenterLat = 0.0;
      _mapCenterLng = 0.0;
      _hasSelection = false;
    }
  }

  @override
  void didUpdateWidget(covariant MapLocationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialLatitude != null &&
        widget.initialLongitude != null &&
        (widget.initialLatitude != oldWidget.initialLatitude ||
            widget.initialLongitude != oldWidget.initialLongitude)) {
      setState(() {
        _mapCenterLat = widget.initialLatitude!;
        _mapCenterLng = widget.initialLongitude!;
        _selectedPlaceName = widget.initialPlaceName;
        _selectedAddress = widget.initialAddress;
        _hasSelection = true;
      });
      _mapController.move(
        LatLng(_mapCenterLat, _mapCenterLng),
        _zoom.toDouble(),
      );
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSearchQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _locationService.searchPlaces(cleanQuery);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  void _selectSearchResult(LocationSearchResult result) {
    setState(() {
      _mapCenterLat = result.latitude;
      _mapCenterLng = result.longitude;
      _selectedPlaceName = result.placeName;
      _selectedAddress = result.formattedAddress;
      _hasSelection = true;
      _searchResults = [];
      _searchController.text = result.placeName;
    });
    _mapController.move(
      LatLng(result.latitude, result.longitude),
      _zoom.toDouble(),
    );
    FocusScope.of(context).unfocus();
    widget.onLocationSelected(result);
  }

  Future<void> _reverseGeocodeCenter() async {
    setState(() {
      _isReverseGeocoding = true;
    });

    try {
      final result = await _locationService.reverseGeocode(
        _mapCenterLat,
        _mapCenterLng,
      );
      if (mounted && result != null) {
        setState(() {
          _selectedPlaceName = result.placeName;
          _selectedAddress = result.formattedAddress;
          _hasSelection = true;
          _isReverseGeocoding = false;
        });
        widget.onLocationSelected(result);
      } else if (mounted) {
        setState(() {
          _isReverseGeocoding = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isReverseGeocoding = false;
        });
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final degreesLngPerPixel = 360.0 / (256.0 * math.pow(2, _zoom));
    final rad = _mapCenterLat * math.pi / 180.0;
    final latFactor = math.cos(rad).abs().clamp(0.1, 1.0);
    final degreesLatPerPixel =
        (180.0 / (256.0 * math.pow(2, _zoom))) * latFactor;

    setState(() {
      _mapCenterLng =
          (_mapCenterLng - details.delta.dx * degreesLngPerPixel)
              .clamp(-180.0, 180.0);
      _mapCenterLat =
          (_mapCenterLat + details.delta.dy * degreesLatPerPixel)
              .clamp(-90.0, 90.0);
      _hasSelection = true;
    });

    _mapController.move(
      LatLng(_mapCenterLat, _mapCenterLng),
      _zoom.toDouble(),
    );
  }

  void _onPanEnd(DragEndDetails details) {
    widget.onLocationSelected(
      LocationSearchResult(
        placeName: _selectedPlaceName ?? 'Selected Location',
        formattedAddress:
            _selectedAddress ??
            '${_mapCenterLat.toStringAsFixed(6)}, ${_mapCenterLng.toStringAsFixed(6)}',
        latitude: _mapCenterLat,
        longitude: _mapCenterLng,
      ),
    );
    _reverseGeocodeCenter();
  }

  void _onTapUp(TapUpDetails details, Size size) {
    LatLng? point;
    try {
      point = _mapController.camera.screenOffsetToLatLng(
        details.localPosition,
      );
    } catch (_) {
      point = null;
    }

    if (point == null) {
      final dx = details.localPosition.dx - (size.width / 2.0);
      final dy = details.localPosition.dy - (size.height / 2.0);
      final degreesLngPerPixel = 360.0 / (256.0 * math.pow(2, _zoom));
      final rad = _mapCenterLat * math.pi / 180.0;
      final latFactor = math.cos(rad).abs().clamp(0.1, 1.0);
      final degreesLatPerPixel =
          (180.0 / (256.0 * math.pow(2, _zoom))) * latFactor;

      final newLng = (_mapCenterLng + dx * degreesLngPerPixel).clamp(-180.0, 180.0);
      final newLat = (_mapCenterLat - dy * degreesLatPerPixel).clamp(-90.0, 90.0);
      point = LatLng(newLat, newLng);
    }

    setState(() {
      _mapCenterLat = point!.latitude;
      _mapCenterLng = point.longitude;
      _hasSelection = true;
    });

    _mapController.move(
      LatLng(_mapCenterLat, _mapCenterLng),
      _zoom.toDouble(),
    );

    widget.onLocationSelected(
      LocationSearchResult(
        placeName: _selectedPlaceName ?? 'Selected Location',
        formattedAddress:
            _selectedAddress ??
            '${_mapCenterLat.toStringAsFixed(6)}, ${_mapCenterLng.toStringAsFixed(6)}',
        latitude: _mapCenterLat,
        longitude: _mapCenterLng,
      ),
    );
    _reverseGeocodeCenter();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      _zoom = camera.zoom.round().clamp(2, 18);
    }
  }

  void _zoomIn() {
    if (_zoom < 18) {
      setState(() {
        _zoom++;
      });
      _mapController.move(
        LatLng(_mapCenterLat, _mapCenterLng),
        _zoom.toDouble(),
      );
    }
  }

  void _zoomOut() {
    if (_zoom > 2) {
      setState(() {
        _zoom--;
      });
      _mapController.move(
        LatLng(_mapCenterLat, _mapCenterLng),
        _zoom.toDouble(),
      );
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_isGettingLocation) return;

    setState(() {
      _isGettingLocation = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await _locationService.getCurrentLocation();

      if (!mounted) return;

      switch (result.status) {
        case CurrentLocationStatus.success:
          if (result.latitude != null && result.longitude != null) {
            setState(() {
              _mapCenterLat = result.latitude!;
              _mapCenterLng = result.longitude!;
              _hasSelection = true;
            });
            _mapController.move(
              LatLng(result.latitude!, result.longitude!),
              _zoom.toDouble(),
            );
            final loc = LocationSearchResult(
              placeName: 'My Current Location',
              formattedAddress:
                  '${result.latitude!.toStringAsFixed(6)}, ${result.longitude!.toStringAsFixed(6)}',
              latitude: result.latitude!,
              longitude: result.longitude!,
            );
            widget.onLocationSelected(loc);
            _reverseGeocodeCenter();
          }
          break;

        case CurrentLocationStatus.permissionDenied:
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission was denied. You can search, pick a location from the map, or enter coordinates manually.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          break;

        case CurrentLocationStatus.permissionPermanentlyDenied:
          messenger.showSnackBar(
            SnackBar(
              content: const Text(
                'Location permission is permanently denied. You can select your location on the map.',
              ),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: () {
                  _locationService.openAppSettings();
                },
              ),
            ),
          );
          break;

        case CurrentLocationStatus.servicesDisabled:
          messenger.showSnackBar(
            SnackBar(
              content: const Text(
                'Location services are turned off.',
              ),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: () {
                  _locationService.openLocationSettings();
                },
              ),
            ),
          );
          break;

        case CurrentLocationStatus.timeout:
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Location request timed out. Please pick a location from the map.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          break;

        case CurrentLocationStatus.unavailable:
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                result.message ??
                    'Current location service is unavailable. Please pick from the map.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Search Bar
        TextField(
          key: const Key('location_search_input'),
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search for a place or address',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                          });
                        },
                      )
                    : null),
          ),
          onChanged: _onSearchQueryChanged,
          onSubmitted: _executeSearch,
        ),

        // Search Results List (if query returned matches)
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Card(
            key: const Key('location_search_results_card'),
            elevation: 4,
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: AppSpacing.radiusMd,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchResults.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
              itemBuilder: (context, index) {
                final item = _searchResults[index];
                return ListTile(
                  key: Key('search_result_item_$index'),
                  dense: true,
                  leading: Icon(
                    Icons.place_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    item.placeName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    item.formattedAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () => _selectSearchResult(item),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.md),

        // 2. Real Interactive OpenStreetMap Container
        ClipRRect(
          borderRadius: AppSpacing.radiusLg,
          child: Container(
            height: 240,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: AppSpacing.radiusLg,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);

                return Stack(
                  children: [
                    // Base Real Interactive OpenStreetMap Map Viewport
                    Positioned.fill(
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: LatLng(_mapCenterLat, _mapCenterLng),
                          initialZoom: _zoom.toDouble(),
                          minZoom: 2.0,
                          maxZoom: 18.0,
                          onPositionChanged: _onPositionChanged,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName:
                                'com.digitalshare.digital_share',
                            errorTileCallback: (tile, error, stackTrace) {},
                          ),
                          if (_hasSelection)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(_mapCenterLat, _mapCenterLng),
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.topCenter,
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    size: 42,
                                    color: theme.colorScheme.primary,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          const SimpleAttributionWidget(
                            source: Text('© OpenStreetMap contributors'),
                          ),
                        ],
                      ),
                    ),

                    // Gesture layer for dragging and tapping
                    Positioned.fill(
                      child: GestureDetector(
                        key: const Key('interactive_map_canvas'),
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) => _onPanUpdate(details, size),
                        onPanEnd: _onPanEnd,
                        onTapUp: (details) => _onTapUp(details, size),
                      ),
                    ),

                // Top-left Coordinate Badge
                Positioned(
                  top: 10,
                  left: 10,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white24,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '${_mapCenterLat.toStringAsFixed(4)}°, ${_mapCenterLng.toStringAsFixed(4)}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                // Top-right Zoom In / Out Controls
                Positioned(
                  top: 10,
                  right: 10,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white24,
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            InkWell(
                              key: const Key('map_zoom_in'),
                              onTap: _zoomIn,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(6.0),
                                child: Icon(
                                  Icons.add_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                            Container(
                              width: 24,
                              height: 0.5,
                              color: Colors.white24,
                            ),
                            InkWell(
                              key: const Key('map_zoom_out'),
                              onTap: _zoomOut,
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(8),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(6.0),
                                child: Icon(
                                  Icons.remove_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom-right Floating "Use Current Location" Button
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: FloatingActionButton.small(
                    key: const Key('use_current_location_button'),
                    heroTag: 'use_current_location_fab',
                    tooltip: _isGettingLocation
                        ? 'Getting your location...'
                        : 'Use Current Location',
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: theme.colorScheme.primary,
                    onPressed:
                        _isGettingLocation ? null : _useCurrentLocation,
                    child: _isGettingLocation
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.my_location_rounded, size: 20),
                  ),
                ),

                // Bottom-left Helper hint / Loading indicator
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _isGettingLocation
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Getting your location...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Pan or tap map to pick',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),

        const SizedBox(height: AppSpacing.md),

        // 3. Selected Location Card
        Card(
          key: const Key('selected_location_card'),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.radiusMd,
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.place_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Selected Location',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    if (_isReverseGeocoding)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_hasSelection) ...[
                  if (_selectedPlaceName != null &&
                      _selectedPlaceName!.isNotEmpty)
                    Text(
                      _selectedPlaceName!,
                      key: const Key('selected_place_name'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (_selectedAddress != null &&
                      _selectedAddress!.isNotEmpty &&
                      _selectedAddress != _selectedPlaceName)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        _selectedAddress!,
                        key: const Key('selected_formatted_address'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${_mapCenterLat.toStringAsFixed(6)}, ${_mapCenterLng.toStringAsFixed(6)}',
                    key: const Key('selected_coordinates'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ] else ...[
                  Text(
                    'No location selected yet. Tap the map or search above.',
                    key: const Key('no_location_selected_text'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
