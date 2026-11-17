import '../operations_intelligence_models.dart';
import '../operations_intelligence_repository.dart';

/// Intelligence Action Centre: Manages the lifecycle of operational actions.
/// Enforces preview, permission check, human approval, and audit trails.
class IntelligenceActionCentre {
  final OperationsIntelligenceRepository repository;

  const IntelligenceActionCentre(this.repository);

  /// Creates an action proposal linked to an insight.
  Future<ActionProposal> proposeAction({
    required String tenantId,
    String? locationId,
    required String insightId,
    required ActionType actionType,
    required Map<String, dynamic> payload,
    required String previewSummary,
    String requiredPermission = 'inventory.manage',
  }) async {
    final proposal = ActionProposal(
      id: '',
      tenantId: tenantId,
      locationId: locationId,
      insightId: insightId,
      actionType: actionType,
      payload: payload,
      previewSummary: previewSummary,
      requiredPermission: requiredPermission,
      status: ActionStatus.pendingApproval,
      createdAt: DateTime.now(),
    );

    final actionId = await repository.createAction(proposal);
    return proposal.copyWith(id: actionId);
  }

  /// Human decision: Approve or reject an action proposal.
  Future<Map<String, dynamic>> decideAction({
    required String tenantId,
    required String actionId,
    required bool approve,
    String note = '',
  }) async {
    return await repository.decideAction(
      tenantId: tenantId,
      actionId: actionId,
      approve: approve,
      note: note,
    );
  }

  /// Updates the status lifecycle of an insight (Acknowledged, Resolved, Dismissed).
  Future<bool> transitionInsight({
    required String tenantId,
    required String insightId,
    required InsightStatus newStatus,
    String? resolutionNote,
  }) async {
    return await repository.updateInsightStatus(
      tenantId: tenantId,
      insightId: insightId,
      status: newStatus,
      resolutionNote: resolutionNote,
    );
  }
}
