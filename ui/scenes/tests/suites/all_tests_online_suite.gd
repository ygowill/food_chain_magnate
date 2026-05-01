# Online, resume, resync, lobby, and persistence tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(_host) -> Array[Dictionary]:
	var tests: Array[Dictionary] = [
		{
			"name": "NetClientParseConnectTokenUrlTest",
			"fn": func() -> Result: return TestRefs.NetClientParseConnectTokenUrlTestClass.run(),
		},
		{
			"name": "OnlineClientHelloConnectTokenTest",
			"fn": func() -> Result: return TestRefs.OnlineClientHelloConnectTokenTestClass.run(),
		},
		{
			"name": "PlatformConnectTokenAutoJoinTest",
			"fn": func() -> Result: return TestRefs.PlatformConnectTokenAutoJoinTestClass.run(),
		},
		{
			"name": "OnlineResumeRoomLobbyTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeRoomLobbyTestClass.run(),
		},
		{
			"name": "OnlineResumeArchiveRecoveryTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeArchiveRecoveryTestClass.run(),
		},
		{
			"name": "OnlineResumeStartValidationTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeStartValidationTestClass.run(),
		},
		{
			"name": "OnlineResumeFullSnapshotBootstrapTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeFullSnapshotBootstrapTestClass.run(),
		},
		{
			"name": "OnlineResumeSingleFullEngineCacheTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeSingleFullEngineCacheTestClass.run(),
		},
		{
			"name": "OnlineResumeFullHistoryBaselineSelectionTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeFullHistoryBaselineSelectionTestClass.run(),
		},
		{
			"name": "NetClientOnlineResumeCachedTimelineForwardingTest",
			"fn": func() -> Result: return TestRefs.NetClientOnlineResumeCachedTimelineForwardingTestClass.run(),
		},
		{
			"name": "OnlineResumeFullArchiveExportTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeFullArchiveExportTestClass.run(),
		},
		{
			"name": "OnlineClientDisconnectPreserveContextTest",
			"fn": func() -> Result: return TestRefs.OnlineClientDisconnectPreserveContextTestClass.run(),
		},
		{
			"name": "OnlineClientGameStartedReconnectTest",
			"fn": func() -> Result: return TestRefs.OnlineClientGameStartedReconnectTestClass.run(),
		},
		{
			"name": "OnlineClientConfigBootstrapOverridesTest",
			"fn": func() -> Result: return TestRefs.OnlineClientConfigBootstrapOverridesTestClass.run(),
		},
		{
			"name": "GameMenuDebugControllerOnlineQuitTest",
			"fn": func() -> Result: return TestRefs.GameMenuDebugControllerOnlineQuitTestClass.run(),
		},
		{
			"name": "GameOverOnlineReturnFlowTest",
			"fn": func() -> Result: return TestRefs.GameOverOnlineReturnFlowTestClass.run(),
		},
		{
			"name": "GameMenuDebugControllerOnlineSurrenderQuitTest",
			"fn": func() -> Result: return await TestRefs.GameMenuDebugControllerOnlineSurrenderQuitTestClass.run(),
		},
		{
			"name": "GameMenuControllerOnlineForfeitConfirmTest",
			"fn": func() -> Result: return await TestRefs.GameMenuControllerOnlineForfeitConfirmTestClass.run(),
		},
		{
			"name": "OnlineRestructuringReopenPendingTest",
			"fn": func() -> Result: return TestRefs.OnlineRestructuringReopenPendingTestClass.run(),
		},
		{
			"name": "OnlineRoomManagerTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomManagerTestClass.run(),
		},
		{
			"name": "OnlineRoomListTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomListTestClass.run(),
		},
		{
			"name": "OnlineLobbyRoomListControllerTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyRoomListControllerTestClass.run(),
		},
		{
			"name": "OnlineLobbyRoomStateRendererTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyRoomStateRendererTestClass.run(),
		},
		{
			"name": "OnlineLobbyRoomConfigSyncControllerTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyRoomConfigSyncControllerTestClass.run(),
		},
		{
			"name": "OnlineMatchBootstrapResumeHistoryGateTest",
			"fn": func() -> Result: return TestRefs.OnlineMatchBootstrapResumeHistoryGateTestClass.run(),
		},
		{
			"name": "OnlineMatchBootstrapServerFlowTest",
			"fn": func() -> Result: return TestRefs.OnlineMatchBootstrapServerFlowTestClass.run(),
		},
		{
			"name": "OnlineStartGameReplayTest",
			"fn": func() -> Result: return TestRefs.OnlineStartGameReplayTestClass.run(),
		},
		{
			"name": "MatchFinalizeParticipantLogoPayloadTest",
			"fn": func() -> Result: return TestRefs.MatchFinalizeParticipantLogoPayloadTestClass.run(),
		},
		{
			"name": "OnlineResyncArchiveTest",
			"fn": func() -> Result: return TestRefs.OnlineResyncArchiveTestClass.run(),
		},
		{
			"name": "ServerResyncGuardTest",
			"fn": func() -> Result: return TestRefs.ServerResyncGuardTestClass.run(),
		},
		{
			"name": "OnlineClientResyncSnapshotChunkTest",
			"fn": func() -> Result: return TestRefs.OnlineClientResyncSnapshotChunkTestClass.run(),
		},
		{
			"name": "OnlineClientRewindToTurnStartMetaTest",
			"fn": func() -> Result: return TestRefs.OnlineClientRewindToTurnStartMetaTestClass.run(),
		},
		{
			"name": "OnlineClientResyncDeltaApplyTest",
			"fn": func() -> Result: return TestRefs.OnlineClientResyncDeltaApplyTestClass.run(),
		},
		{
			"name": "OnlineClientResyncRoomIsolationTest",
			"fn": func() -> Result: return TestRefs.OnlineClientResyncRoomIsolationTestClass.run(),
		},
		{
			"name": "OnlineRewindToTurnStartTest",
			"fn": func() -> Result: return TestRefs.OnlineRewindToTurnStartTestClass.run(),
		},
		{
			"name": "ForfeitPlayerActionTest",
			"fn": func() -> Result: return TestRefs.ForfeitPlayerActionTestClass.run(),
		},
		{
			"name": "ForfeitPlayerStateAccessTest",
			"fn": func() -> Result: return TestRefs.ForfeitPlayerStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "OnlineRoomSpectatorTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomSpectatorTestClass.run(),
		},
		{
			"name": "OnlineLobbyDisconnectReclaimTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyDisconnectReclaimTestClass.run(),
		},
		{
			"name": "OnlineLobbyDisconnectGraceReleaseTest",
			"fn": func() -> Result: return await TestRefs.OnlineLobbyDisconnectGraceReleaseTestClass.run(),
		},
		{
			"name": "OnlineDisconnectGraceReconnectTest",
			"fn": func() -> Result: return await TestRefs.OnlineDisconnectGraceReconnectTestClass.run(),
		},
		{
			"name": "OnlineForfeitAndLeaveRoomTest",
			"fn": func() -> Result: return TestRefs.OnlineForfeitAndLeaveRoomTestClass.run(),
		},
		{
			"name": "GameOnlineResyncResumeTicketRetryPolicyTest",
			"fn": func() -> Result: return await TestRefs.GameOnlineResyncResumeTicketRetryPolicyTestClass.run(),
		},
		{
			"name": "GameOnlineResyncReconnectFlowTest",
			"fn": func() -> Result: return await TestRefs.GameOnlineResyncReconnectFlowTestClass.run(),
		},
		{
			"name": "GameOnlineResumeProgressSyncTest",
			"fn": func() -> Result: return await TestRefs.GameOnlineResumeProgressSyncTestClass.run(),
		},
		{
			"name": "GameOnlineResyncRequestRejectionTest",
			"fn": func() -> Result: return TestRefs.GameOnlineResyncRequestRejectionTestClass.run(),
		},
		{
			"name": "OnlineResumeDeltaStoreContractTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeDeltaStoreContractTestClass.run(),
		},
		{
			"name": "OnlineLobbyResumeControllerTest",
			"fn": func() -> Result: return await TestRefs.OnlineLobbyResumeControllerTestClass.run(),
		},
		{
			"name": "OnlineLobbyInGameEntryFallbackTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyInGameEntryFallbackTestClass.run(),
		},
		{
			"name": "OnlineRoomPersistenceRecoveryTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomPersistenceRecoveryTestClass.run(),
		},
		{
			"name": "OnlineRoundAutosaveTest",
			"fn": func() -> Result: return TestRefs.OnlineRoundAutosaveTestClass.run(),
		},
		{
			"name": "ExportMatchArtifactsContractTest",
			"fn": func() -> Result: return TestRefs.ExportMatchArtifactsContractTestClass.run(),
		},
		{
			"name": "OnlineLobbyPersistenceRecoveryTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyPersistenceRecoveryTestClass.run(),
		},
		{
			"name": "ServerIdentityStoreTest",
			"fn": func() -> Result: return TestRefs.ServerIdentityStoreTestClass.run(),
		},
		{
			"name": "GameStartupDirectResumeGuardTest",
			"fn": func() -> Result: return TestRefs.GameStartupDirectResumeGuardTestClass.run(),
		},
		{
			"name": "GameStartupOnlineResumeControllerTest",
			"fn": func() -> Result: return await TestRefs.GameStartupOnlineResumeControllerTestClass.run(),
		},
		{
			"name": "OnlineRoomSeedRandomStableTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomSeedRandomStableTestClass.run(),
		},
	]
	return tests
