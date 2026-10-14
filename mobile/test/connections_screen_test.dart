import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_share/models/saved_connection.dart';
import 'package:digital_share/screens/connections/connections_screen.dart';
import 'package:digital_share/services/connection_service.dart';

class MockConnectionService extends ConnectionService {
  final List<SavedConnection> mockConnections;
  bool deleteCalled = false;
  String? lastDeletedShareId;

  MockConnectionService({this.mockConnections = const []});

  @override
  Future<List<SavedConnection>> getConnections() async {
    return mockConnections;
  }

  @override
  Future<void> deleteConnection(String shareId) async {
    deleteCalled = true;
    lastDeletedShareId = shareId;
  }
}

void main() {
  group('ConnectionsScreen Widget Tests', () {
    testWidgets('Renders empty state when no connections are saved', (WidgetTester tester) async {
      final mockService = MockConnectionService(mockConnections: []);

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionsScreen(connectionService: mockService),
        ),
      );

      await tester.pump(); // Start load
      await tester.pump(const Duration(milliseconds: 500)); // Finish load

      expect(find.text('My Connections'), findsOneWidget);
      expect(find.text('No Connections Yet'), findsOneWidget);
      expect(
        find.text('Scan another person\'s Digital Share QR code to save their live digital card here.'),
        findsOneWidget,
      );
    });

    testWidgets('Renders list of saved connections with search filter', (WidgetTester tester) async {
      final sampleConnections = [
        SavedConnection(
          shareId: 'share-1',
          fullName: 'Alice Walker',
          email: 'alice@example.com',
          jobTitle: 'VP of Product',
          company: 'Acme Corp',
          savedAtUtc: DateTime.utc(2026, 10, 8, 10, 0, 0),
        ),
        SavedConnection(
          shareId: 'share-2',
          fullName: 'Bob Martinez',
          email: 'bob@example.com',
          jobTitle: 'Lead Architect',
          company: 'TechFlow',
          savedAtUtc: DateTime.utc(2026, 10, 8, 11, 0, 0),
        ),
      ];

      final mockService = MockConnectionService(mockConnections: sampleConnections);

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionsScreen(connectionService: mockService),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Alice Walker'), findsOneWidget);
      expect(find.text('VP of Product • Acme Corp'), findsOneWidget);
      expect(find.text('Bob Martinez'), findsOneWidget);
      expect(find.text('Lead Architect • TechFlow'), findsOneWidget);

      // Test Search
      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pump();

      expect(find.text('Alice Walker'), findsOneWidget);
      expect(find.text('Bob Martinez'), findsNothing);
    });
  });
}
