#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The sanctioned progress helper (architecture.md section 2.2 bans raw WriteProgress in
/// cmdlet bodies): one place that builds ProgressRecord objects with Write-Progress
/// defaults — omitted -Status renders as "Processing", -Completed maps to
/// ProgressRecordType.Completed — and emits them through the hosting cmdlet.
/// </summary>
internal static class ProgressBridge
{
    /// <summary>Write-Progress parity emission.</summary>
    internal static void Write(Cmdlet host, int activityId, string activity,
        string? status = null,
        string? currentOperation = null,
        int percentComplete = -1,
        int parentActivityId = -1,
        bool completed = false)
    {
        // Write-Progress renders "Processing" when -Status is not supplied.
        ProgressRecord record = new(activityId, activity, status ?? "Processing");
        if (currentOperation != null)
            record.CurrentOperation = currentOperation;
        if (percentComplete >= 0)
            record.PercentComplete = percentComplete;
        if (parentActivityId >= 0)
            record.ParentActivityId = parentActivityId;
        if (completed)
            record.RecordType = ProgressRecordType.Completed;
        host.WriteProgress(record);
    }
}
