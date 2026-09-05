$ErrorActionPreference = 'Stop'
$evidence = Join-Path $PSScriptRoot '..\test\evidence\oa-phone-withdraw-20260904'
function ReadEvidence([string]$Name) {
  Get-Content -LiteralPath (Join-Path $evidence $Name) -Raw | ConvertFrom-Json
}
$initial = ReadEvidence '04-server-submitted.json'
$restart = ReadEvidence '09-server-restarted.json'
$partial = ReadEvidence '11-server-partial.json'
$final = ReadEvidence '13-server-final.json'
$read = ReadEvidence '15-server-read.json'
$text = ReadEvidence '16-server-cancel-text.json'
$local = ReadEvidence '18-local-receipt.json'
$originalId = '3b79ae54-2b23-422c-9ead-cb8153fdf4a8'
$newId = '4b57f546-639e-49b7-bc9f-4fbbc69f0496'
$noticeId = 'fc6afcf0-881f-4be7-a331-f737a082cf34'
$original = @($initial.requests | Where-Object id -eq $originalId)
$newPartial = @($partial.requests | Where-Object id -eq $newId)
$newFinal = @($final.requests | Where-Object id -eq $newId)
$checks = [ordered]@{
  firstSubmittedWithFourPending = ($original.Count -eq 1 -and $original[0].status -eq 'submitted' -and @($original[0].tasks | Where-Object status -eq 'pending').Count -eq 4)
  restartHasTwoDistinctRequests = ($restart.matchCount -eq 2 -and @($restart.requests.clientRequestId | Sort-Object -Unique).Count -eq 2)
  originalRemainsWithdrawn = (@($restart.requests | Where-Object { $_.id -eq $originalId -and $_.status -eq 'withdrawn' }).Count -eq 1)
  partialApprovalWaitsForThree = ($newPartial.Count -eq 1 -and $newPartial[0].status -eq 'submitted' -and @($newPartial[0].tasks | Where-Object status -eq 'approved').Count -eq 1 -and @($newPartial[0].tasks | Where-Object status -eq 'pending').Count -eq 3 -and 'approve' -notin $newPartial[0].allowedActions)
  bothWithdrawnWithoutOperableActions = ($final.matchCount -eq 2 -and @($final.requests | Where-Object status -eq 'withdrawn').Count -eq 2 -and @($final.requests | Where-Object { $_.allowedActions.Count -ne 0 }).Count -eq 0)
  completedApprovalIsNotRewritten = ($newFinal.Count -eq 1 -and @($newFinal[0].tasks | Where-Object status -eq 'approved').Count -eq 1 -and @($newFinal[0].tasks | Where-Object status -eq 'canceled').Count -eq 3)
  serverReadReceiptConfirmed = (@($read.requests.notifications | Where-Object { $_.id -eq $noticeId -and $_.isRead -and $_.readAt }).Count -eq 1)
  localReadReceiptSent = (@($local.targetRead | Where-Object { $_.notification_id -eq $noticeId -and $_.state -eq 'sent' }).Count -eq 1 -and $local.outboxCount -eq 0)
}
$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
if ($failed.Count) { throw ('Evidence checks failed: ' + ($failed.Key -join ', ')) }
[ordered]@{
  evidenceChecks = $checks
  verifiedCount = $checks.Count
  cancellationTextDefectConfirmed = (@($text.cancellationText | Where-Object { $_.saysOtherHandlerCompleted -and -not $_.mentionsWithdrawal }).Count -eq 1)
  conclusion = 'partial_pass_with_notification_defect'
} | ConvertTo-Json -Depth 4
