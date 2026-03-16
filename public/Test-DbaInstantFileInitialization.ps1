function Test-DbaInstantFileInitialization {
    <#
    .SYNOPSIS
        Tests whether Instant File Initialization (IFI) is properly configured for SQL Server Engine service accounts.

    .DESCRIPTION
        Audits Instant File Initialization (IFI) configuration for all SQL Server Engine services on the specified computer(s).

        IFI allows SQL Server to skip zeroing out data file space during file creation and auto-growth operations, which can dramatically speed up database creation, restore operations, and auto-growth events. Microsoft recommends enabling IFI as a best practice for all SQL Server installations.

        IFI is controlled by the Windows "Perform Volume Maintenance Tasks" privilege (SeManageVolumePrivilege). The recommended approach is to grant this privilege to the virtual service account "NT SERVICE\<ServiceName>" rather than to the actual service account (StartName), as this follows the principle of least privilege and is account-independent.

        This command checks both the virtual service account (NT SERVICE\<ServiceName>) and the actual start account (StartName) to determine:
        - IsEnabled: IFI is enabled via either account (the service will benefit from IFI)
        - IsBestPractice: IFI is enabled via the virtual service account only (the recommended configuration)

        Note: This command checks direct privilege assignments only. IFI may also be enabled indirectly via group membership (e.g., Administrators), which is not detected by this command.

        Requires Local Admin rights on destination computer(s).

        References:
        https://docs.microsoft.com/en-us/sql/relational-databases/databases/database-instant-file-initialization
        https://blog.ordix.de/instant-file-initialization-microsoft-sql-server-set-up-check

    .PARAMETER ComputerName
        Specifies the SQL Server host computer(s) to test IFI configuration on. Accepts server names, IP addresses, or DbaInstance objects.

    .PARAMETER Credential
        Specifies a PSCredential object used to authenticate to the target computer(s) when the current user account is insufficient.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: IFI, Privilege, Security, BestPractice, OS
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaInstantFileInitialization

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server Engine service found on each computer tested.

        Default display properties (via Select-DefaultView):
        - ComputerName: The target computer name
        - InstanceName: The SQL Server instance name
        - ServiceName: The Windows service name (e.g. MSSQLSERVER, MSSQL$INSTANCENAME)
        - StartName: The actual Windows account running the service
        - IsEnabled: Boolean indicating if IFI is enabled via either the virtual or start account
        - IsBestPractice: Boolean indicating if IFI is enabled via the virtual service account (NT SERVICE\<ServiceName>) only

        Additional properties available:
        - ServiceNameIFI: Boolean indicating if the virtual service account (NT SERVICE\<ServiceName>) has IFI privilege
        - StartNameIFI: Boolean indicating if the actual start account (StartName) has IFI privilege

    .EXAMPLE
        PS C:\> Test-DbaInstantFileInitialization -ComputerName sqlserver2019

        Tests IFI configuration for all SQL Server Engine services on sqlserver2019.

    .EXAMPLE
        PS C:\> Test-DbaInstantFileInitialization -ComputerName sql1, sql2, sql3

        Tests IFI configuration for all SQL Server Engine services on sql1, sql2, and sql3.

    .EXAMPLE
        PS C:\> 'sql1', 'sql2' | Test-DbaInstantFileInitialization

        Tests IFI configuration for all SQL Server Engine services on sql1 and sql2.

    .EXAMPLE
        PS C:\> Test-DbaInstantFileInitialization -ComputerName sqlserver2019 | Where-Object IsBestPractice -eq $false

        Returns SQL Server services on sqlserver2019 where IFI is not configured as best practice.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    process {
        foreach ($computer in $ComputerName) {
            try {
                Write-Message -Level Verbose -Message "Getting SQL Server Engine services on $computer"
                $splatGetService = @{
                    ComputerName    = $computer
                    Credential      = $Credential
                    Type            = "Engine"
                    EnableException = $EnableException
                }
                $services = Get-DbaService @splatGetService
            } catch {
                Stop-Function -Message "Failed to get SQL Server services on $computer" -ErrorRecord $_ -Target $computer -Continue
            }

            if (-not $services) {
                Write-Message -Level Verbose -Message "No SQL Server Engine services found on $computer"
                continue
            }

            try {
                Write-Message -Level Verbose -Message "Getting Windows privileges on $computer"
                $splatGetPrivilege = @{
                    ComputerName    = $computer
                    Credential      = $Credential
                    EnableException = $EnableException
                }
                $privileges = Get-DbaPrivilege @splatGetPrivilege
            } catch {
                Stop-Function -Message "Failed to get privileges on $computer" -ErrorRecord $_ -Target $computer -Continue
            }

            foreach ($service in $services) {
                Write-Message -Level Verbose -Message "Checking IFI for service $($service.ServiceName) on $computer"

                $serviceNameIFI = ($privileges | Where-Object User -eq "NT SERVICE\$($service.ServiceName)").InstantFileInitialization -eq $true
                $startNameIFI = ($privileges | Where-Object User -eq $service.StartName).InstantFileInitialization -eq $true

                $isEnabled = $serviceNameIFI -or $startNameIFI
                $isBestPractice = $serviceNameIFI -and -not $startNameIFI

                [PSCustomObject]@{
                    ComputerName   = $service.ComputerName
                    InstanceName   = $service.InstanceName
                    ServiceName    = $service.ServiceName
                    StartName      = $service.StartName
                    ServiceNameIFI = $serviceNameIFI
                    StartNameIFI   = $startNameIFI
                    IsEnabled      = $isEnabled
                    IsBestPractice = $isBestPractice
                } | Select-DefaultView -Property ComputerName, InstanceName, ServiceName, StartName, IsEnabled, IsBestPractice
            }
        }
    }
}
