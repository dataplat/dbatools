function Get-DbaBackupDevice {
    <#
    .SYNOPSIS
        Retrieves configured backup devices from SQL Server instances for inventory and management

    .DESCRIPTION
        This function returns all backup devices configured on SQL Server instances, including their type (disk, tape, URL), physical locations, and settings. Backup devices are logical names that map to physical backup destinations, allowing DBAs to create standardized backup locations that can be referenced in backup scripts and maintenance plans. Use this to audit backup device configurations across your environment, verify backup paths are accessible, or document your backup infrastructure for compliance and disaster recovery planning.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.BackupDevice

        Returns one BackupDevice object per configured backup device on each SQL Server instance.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The name of the SQL Server instance
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The logical name of the backup device
        - BackupDeviceType: The type of backup device (Disk, Tape, or Url)
        - PhysicalLocation: The physical path or location of the backup device (file path, tape device, or URL)
        - SkipTapeLabel: Boolean indicating whether to skip tape label validation

        Additional properties available (from SMO BackupDevice object):
        - Urn: The Uniform Resource Name identifying the backup device
        - State: The state of the SMO object (Existing, Creating, Pending, etc.)
        - Parent: Reference to the parent Server object

        All properties from the SMO BackupDevice object are accessible using Select-Object *.

    .NOTES
        Tags: Backup, General
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaBackupDevice

    .EXAMPLE
        PS C:\> Get-DbaBackupDevice -SqlInstance localhost

        Returns all Backup Devices on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaBackupDevice -SqlInstance localhost, sql2016

        Returns all Backup Devices for the local and sql2016 SQL Server instances

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($backupDevice in $server.BackupDevices) {
                Add-Member -Force -InputObject $backupDevice -MemberType NoteProperty -Name ComputerName -value $backupDevice.Parent.ComputerName
                Add-Member -Force -InputObject $backupDevice -MemberType NoteProperty -Name InstanceName -value $backupDevice.Parent.ServiceName
                Add-Member -Force -InputObject $backupDevice -MemberType NoteProperty -Name SqlInstance -value $backupDevice.Parent.DomainInstanceName

                Select-DefaultView -InputObject $backupDevice -Property ComputerName, InstanceName, SqlInstance, Name, BackupDeviceType, PhysicalLocation, SkipTapeLabel
            }
        }
    }
}