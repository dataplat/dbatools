#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaDbLogShippingCommand
{
    [Parameter(Position = 0, Mandatory = true)]
    [Alias("Source", "SourceServerInstance", "SourceSqlServerSqlServer")]
    [ValidateNotNullOrEmpty]
    public DbaInstanceParameter? SourceSqlInstance { get; set; }

    [Parameter(Position = 1, Mandatory = true)]
    [Alias("Destination", "DestinationServerInstance", "DestinationSqlServer")]
    [ValidateNotNullOrEmpty]
    public DbaInstanceParameter[]? DestinationSqlInstance { get; set; }

    [Parameter(Position = 2)]
    public PSCredential? SourceSqlCredential { get; set; }

    [Parameter(Position = 3)]
    public PSCredential? SourceCredential { get; set; }

    [Parameter(Position = 4)]
    public PSCredential? DestinationSqlCredential { get; set; }

    [Parameter(Position = 5)]
    public PSCredential? DestinationCredential { get; set; }

    [Parameter(Position = 6, Mandatory = true, ValueFromPipeline = true)]
    public object[]? Database { get; set; }

    [Parameter(Position = 7)]
    [Alias("BackupNetworkPath")]
    public string? SharedPath { get; set; }

    [Parameter(Position = 8)]
    [Alias("BackupLocalPath")]
    public string? LocalPath { get; set; }

    [Parameter(Position = 9)]
    public string? AzureBaseUrl { get; set; }

    [Parameter(Position = 10)]
    public string? AzureCredential { get; set; }

    [Parameter(Position = 11)]
    public string? BackupJob { get; set; }

    [Parameter(Position = 12)]
    public int BackupRetention { get; set; }

    [Parameter(Position = 13)]
    public string? BackupSchedule { get; set; }

    [Parameter(Position = 14)]
    [ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
    public object? BackupScheduleFrequencyType { get; set; }

    [Parameter(Position = 15)]
    public object[]? BackupScheduleFrequencyInterval { get; set; }

    [Parameter(Position = 16)]
    [ValidateSet("Time", "Seconds", "Minutes", "Hours")]
    public object? BackupScheduleFrequencySubdayType { get; set; }

    [Parameter(Position = 17)]
    public int BackupScheduleFrequencySubdayInterval { get; set; }

    [Parameter(Position = 18)]
    [ValidateSet("Unused", "First", "Second", "Third", "Fourth", "Last")]
    public object? BackupScheduleFrequencyRelativeInterval { get; set; }

    [Parameter(Position = 19)]
    public int BackupScheduleFrequencyRecurrenceFactor { get; set; }

    [Parameter(Position = 20)]
    public string? BackupScheduleStartDate { get; set; }

    [Parameter(Position = 21)]
    public string? BackupScheduleEndDate { get; set; }

    [Parameter(Position = 22)]
    public string? BackupScheduleStartTime { get; set; }

    [Parameter(Position = 23)]
    public string? BackupScheduleEndTime { get; set; }

    [Parameter(Position = 24)]
    public int BackupThreshold { get; set; }

    [Parameter(Position = 25)]
    public string? CopyDestinationFolder { get; set; }

    [Parameter(Position = 26)]
    public string? CopyJob { get; set; }

    [Parameter(Position = 27)]
    public int CopyRetention { get; set; }

    [Parameter(Position = 28)]
    public string? CopySchedule { get; set; }

    [Parameter(Position = 29)]
    [ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
    public object? CopyScheduleFrequencyType { get; set; }

    [Parameter(Position = 30)]
    public object[]? CopyScheduleFrequencyInterval { get; set; }

    [Parameter(Position = 31)]
    [ValidateSet("Time", "Seconds", "Minutes", "Hours")]
    public object? CopyScheduleFrequencySubdayType { get; set; }

    [Parameter(Position = 32)]
    public int CopyScheduleFrequencySubdayInterval { get; set; }

    [Parameter(Position = 33)]
    [ValidateSet("Unused", "First", "Second", "Third", "Fourth", "Last")]
    public object? CopyScheduleFrequencyRelativeInterval { get; set; }

    [Parameter(Position = 34)]
    public int CopyScheduleFrequencyRecurrenceFactor { get; set; }

    [Parameter(Position = 35)]
    public string? CopyScheduleStartDate { get; set; }

    [Parameter(Position = 36)]
    public string? CopyScheduleEndDate { get; set; }

    [Parameter(Position = 37)]
    public string? CopyScheduleStartTime { get; set; }

    [Parameter(Position = 38)]
    public string? CopyScheduleEndTime { get; set; }

    [Parameter(Position = 39)]
    public string? FullBackupPath { get; set; }

    [Parameter(Position = 40)]
    public int HistoryRetention { get; set; }

    [Parameter(Position = 41)]
    public string? PrimaryMonitorServer { get; set; }

    [Parameter(Position = 42)]
    public PSCredential? PrimaryMonitorCredential { get; set; }

    [Parameter(Position = 43)]
    [ValidateSet("0", "sqlserver", "1", "windows")]
    public object? PrimaryMonitorServerSecurityMode { get; set; }

    [Parameter(Position = 44)]
    public string? RestoreDataFolder { get; set; }

    [Parameter(Position = 45)]
    public string? RestoreLogFolder { get; set; }

    [Parameter(Position = 46)]
    public int RestoreDelay { get; set; }

    [Parameter(Position = 47)]
    public int RestoreAlertThreshold { get; set; }

    [Parameter(Position = 48)]
    public string? RestoreJob { get; set; }

    [Parameter(Position = 49)]
    public int RestoreRetention { get; set; }

    [Parameter(Position = 50)]
    public string? RestoreSchedule { get; set; }

    [Parameter(Position = 51)]
    [ValidateSet("Daily", "Weekly", "AgentStart", "IdleComputer")]
    public object? RestoreScheduleFrequencyType { get; set; }

    [Parameter(Position = 52)]
    public object[]? RestoreScheduleFrequencyInterval { get; set; }

    [Parameter(Position = 53)]
    [ValidateSet("Time", "Seconds", "Minutes", "Hours")]
    public object? RestoreScheduleFrequencySubdayType { get; set; }

    [Parameter(Position = 54)]
    public int RestoreScheduleFrequencySubdayInterval { get; set; }

    [Parameter(Position = 55)]
    [ValidateSet("Unused", "First", "Second", "Third", "Fourth", "Last")]
    public object? RestoreScheduleFrequencyRelativeInterval { get; set; }

    [Parameter(Position = 56)]
    public int RestoreScheduleFrequencyRecurrenceFactor { get; set; }

    [Parameter(Position = 57)]
    public string? RestoreScheduleStartDate { get; set; }

    [Parameter(Position = 58)]
    public string? RestoreScheduleEndDate { get; set; }

    [Parameter(Position = 59)]
    public string? RestoreScheduleStartTime { get; set; }

    [Parameter(Position = 60)]
    public string? RestoreScheduleEndTime { get; set; }

    [Parameter(Position = 61)]
    public int RestoreThreshold { get; set; }

    [Parameter(Position = 62)]
    public string? SecondaryDatabasePrefix { get; set; }

    [Parameter(Position = 63)]
    public string? SecondaryDatabaseSuffix { get; set; }

    [Parameter(Position = 64)]
    public string? SecondaryMonitorServer { get; set; }

    [Parameter(Position = 65)]
    public PSCredential? SecondaryMonitorCredential { get; set; }

    [Parameter(Position = 66)]
    [ValidateSet("0", "sqlserver", "1", "windows")]
    public object? SecondaryMonitorServerSecurityMode { get; set; }

    [Parameter(Position = 67)]
    public string? StandbyDirectory { get; set; }

    [Parameter(Position = 68)]
    public string? UseBackupFolder { get; set; }

    [Parameter]
    public SwitchParameter BackupScheduleDisabled { get; set; }

    [Parameter]
    public SwitchParameter CompressBackup { get; set; }

    [Parameter]
    public SwitchParameter CopyScheduleDisabled { get; set; }

    [Parameter]
    public SwitchParameter DisconnectUsers { get; set; }

    [Parameter]
    public SwitchParameter Force { get; set; }

    [Parameter]
    public SwitchParameter GenerateFullBackup { get; set; }

    [Parameter]
    public SwitchParameter IgnoreFileChecks { get; set; }

    [Parameter]
    public SwitchParameter NoInitialization { get; set; }

    [Parameter]
    public SwitchParameter NoRecovery { get; set; }

    [Parameter]
    public SwitchParameter PrimaryThresholdAlertEnabled { get; set; }

    [Parameter]
    public SwitchParameter RestoreScheduleDisabled { get; set; }

    [Parameter]
    public SwitchParameter SecondaryThresholdAlertEnabled { get; set; }

    [Parameter]
    public SwitchParameter Standby { get; set; }

    [Parameter]
    public SwitchParameter UseExistingFullBackup { get; set; }


}
