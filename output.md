# Prompt for AI to analyze PowerShell command output columns

You are analyzing a PowerShell command file to document its output properties/columns.

## Task
Review the provided PowerShell command code and identify all output properties/columns that are returned to the user.

## Instructions

1. **Trace all execution paths** including:
   - Default output
   - Switch parameters that modify output (like -Detailed, -Simple, -Raw, etc.)
   - Conditional logic that changes what's returned
   - Different outputs for different input types

2. **For each execution path, identify**:
   - The complete list of property names
   - The data type of each property (string, int, bool, datetime, custom object, etc.)
   - A brief description of what each property contains
   - Which path(s) return this property set

3. **Focus on user-visible output**:
   - Properties added via `Select-Object`, `Add-Member`, or PSCustomObject creation
   - Properties from objects being passed through or returned
   - Ignore internal/private variables not included in output

4. **Handle common dbatools patterns**:
   - `Select-DefaultView` - note which properties are shown by default vs available
   - Pipeline objects with added properties
   - Different object types returned based on conditions

## Output Format

Generate a `.OUTPUTS` section in PowerShell comment-based help format.

### Example 1: SMO Object with Select-DefaultView
```
.OUTPUTS
    Microsoft.SqlServer.Management.Smo.AvailabilityDatabase

    Returns one AvailabilityDatabase object per replica where the database was added. For example, adding one database to an AG with two replicas returns two objects - one for the primary and one for each secondary.

    Default display properties (via Select-DefaultView):
    - ComputerName: The computer name of the SQL Server instance
    - InstanceName: The SQL Server instance name
    - SqlInstance: The full SQL Server instance name (computer\instance)
    - AvailabilityGroup: Name of the availability group
    - LocalReplicaRole: Role of this replica (Primary or Secondary)
    - Name: Database name
    - SynchronizationState: Current synchronization state (NotSynchronizing, Synchronizing, Synchronized, Reverting, Initializing)
    - IsFailoverReady: Boolean indicating if the database is ready for failover
    - IsJoined: Boolean indicating if the database has joined the availability group
    - IsSuspended: Boolean indicating if data movement is suspended

    Additional properties available (from SMO AvailabilityDatabase object):
    - DatabaseGuid: Unique identifier for the database
    - EstimatedDataLoss: Estimated data loss in seconds
    - EstimatedRecoveryTime: Estimated recovery time in seconds
    - FileStreamSendRate: Rate of FILESTREAM data being sent (bytes/sec)
    - GroupDatabaseId: Unique identifier for the database within the AG
    - LastCommitTime: Timestamp of last committed transaction
    - LogSendQueue: Size of log send queue in KB
    - RedoRate: Rate of redo operations (bytes/sec)
    - State: SMO object state (Existing, Creating, Pending, etc.)

    All properties from the base SMO object are accessible even though only default properties are displayed without using Select-Object *.
```

### Example 2: Simple PSCustomObject
```
.OUTPUTS
    PSCustomObject

    Returns one object per counter added to the Data Collector Set.

    Properties:
    - ComputerName: The name of the computer where the Data Collector Set is configured
    - DataCollectorSet: The name of the parent Data Collector Set containing the collector
    - DataCollector: The name of the specific Data Collector within the Collector Set
    - Name: The full path of the performance counter that was added
    - FileName: The output file name where performance counter data will be stored
```

### Example 3: Multiple Output Types (Conditional)
```
.OUTPUTS
    System.String (when -Raw is specified)

    Returns the raw XML configuration as a string.

    PSCustomObject (default)

    Returns configuration details with the following properties:
    - ComputerName: The target server name
    - ConfigName: Name of the configuration setting
    - ConfigValue: Current value of the setting
    - IsDefault: Boolean indicating if this is the default value
    - RequiresRestart: Boolean indicating if changing this requires a restart
```

### Example 4: Different Properties Based on Switch
```
.OUTPUTS
    PSCustomObject

    Default properties:
    - Database: Database name
    - Status: Current backup status (Full, Differential, Log)
    - LastBackupDate: DateTime of the most recent backup
    - SizeMB: Size of the database in megabytes

    When -Detailed is specified, additional properties are included:
    - RecoveryModel: Database recovery model (Simple, Full, BulkLogged)
    - LastFullBackup: DateTime of last full backup
    - LastDiffBackup: DateTime of last differential backup
    - LastLogBackup: DateTime of last transaction log backup
    - BackupPath: Path where backups are stored
    - CompressedBackupSize: Size of compressed backup in MB
```

## Guidelines

- **Start with the .NET type name** (Microsoft.SqlServer.Management.Smo.Database, PSCustomObject, etc.)
- **Provide context** in a brief paragraph about what's returned (quantity, conditions, relationships)
- **Separate default from all available** when using Select-DefaultView
- **Include data types/units** in descriptions (Boolean, DateTime, MB, KB, bytes/sec, etc.)
- **Be specific about conditions** that trigger different outputs
- **Add a closing note** when appropriate about Select-Object * or other access patterns
- **Prioritize useful properties** - skip pure implementation details unless valuable to users