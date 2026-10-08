# Attendance module — reserved for later

Module key: `attendance`. The catalogue entry is inactive and is not assigned to tenants, plans, permissions or app menus. This update separates attendance from Staff; it does not implement attendance tracking.

Staff owns employee profiles, wage rates, manual payroll, payments, advances and load wage accounting. Staff statements, exports and its RPC do not read or record attendance. Payroll uses the payable units and allowances entered by the operator.

The future Attendance module will have its own screen, permissions, API and records. It may reference Staff identities, but enabling Staff will not enable Attendance. Any future payroll integration will be explicit rather than an implicit side effect of recording attendance.

The old `staff_attendance_v630` rows and attendance audit history remain unchanged. Migrate them only when the standalone module's design is implemented and verified. The old Staff attendance RPC action is disabled now; older clients must install this source update to remove its controls.
