import 'package:flutter/material.dart';

import '../models/client_session.dart';

class IndustryWorkspaceScreen extends StatelessWidget {
  final ClientSession session;
  final ClientModule module;
  const IndustryWorkspaceScreen({
    super.key,
    required this.session,
    required this.module,
  });

  static const Map<String, List<(IconData, String, String)>> _features = {
    'restaurant': [
      (
        Icons.table_restaurant_outlined,
        'Tables & Sections',
        'Table/floor configuration',
      ),
      (
        Icons.restaurant_menu_outlined,
        'Menu',
        'Menu items, variants and modifiers',
      ),
      (
        Icons.soup_kitchen_outlined,
        'Kitchen / KOT',
        'Kitchen tickets and preparation status',
      ),
      (Icons.event_seat_outlined, 'Reservations', 'Reservation workflow'),
    ],
    'restaurant_orders': [
      (
        Icons.receipt_long_outlined,
        'Dine-in Orders',
        'Orders linked to tables',
      ),
      (Icons.takeout_dining_outlined, 'Takeaway', 'Fast takeaway workflow'),
      (Icons.delivery_dining_outlined, 'Delivery', 'Delivery order workflow'),
    ],
    'workshop': [
      (Icons.directions_car_outlined, 'Vehicles', 'Customer vehicle registry'),
      (
        Icons.build_outlined,
        'Job Cards',
        'Complaint, diagnosis, parts and labour',
      ),
      (
        Icons.engineering_outlined,
        'Technicians',
        'Technician assignment and status',
      ),
      (
        Icons.request_quote_outlined,
        'Estimates',
        'Estimate-to-invoice workflow',
      ),
    ],
    'healthcare': [
      (
        Icons.personal_injury_outlined,
        'Patients',
        'Patient registry with healthcare-specific access controls',
      ),
      (
        Icons.calendar_month_outlined,
        'Appointments',
        'Doctor/resource scheduling',
      ),
      (
        Icons.medical_information_outlined,
        'Consultations',
        'Clinical workflow extension',
      ),
      (
        Icons.medication_outlined,
        'Pharmacy',
        'Prescription-to-pharmacy workflow',
      ),
    ],
    'lab': [
      (Icons.biotech_outlined, 'Test Catalogue', 'Tests, panels and pricing'),
      (Icons.science_outlined, 'Lab Orders', 'Patient test orders'),
      (Icons.bloodtype_outlined, 'Samples', 'Collection and sample tracking'),
      (
        Icons.description_outlined,
        'Results',
        'Verification and report workflow',
      ),
    ],
    'pharmacy': [
      (
        Icons.medication_outlined,
        'Medicine Catalogue',
        'Batch/expiry-ready inventory extension',
      ),
      (
        Icons.event_busy_outlined,
        'Expiry Monitoring',
        'Expiry and near-expiry workflows',
      ),
      (
        Icons.qr_code_scanner_outlined,
        'Counter POS',
        'Use the POS module for checkout',
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final features =
        _features[module.key] ?? const <(IconData, String, String)>[];
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            module.name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            module.description ?? 'Industry extension workspace',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade100),
            ),
            child: const Text(
              'Industry module foundation is enabled. The platform/template/permission structure is ready; domain-specific transactional records should be installed only with that industry pack so the ERP core stays clean.',
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 330,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.7,
              children: features
                  .map(
                    (f) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Icon(f.$1, size: 34),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.$2,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    f.$3,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
