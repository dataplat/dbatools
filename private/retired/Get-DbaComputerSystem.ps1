function Get-DbaComputerSystem {
    <#
    .SYNOPSIS
        Retrieves comprehensive hardware and system information from Windows computers hosting SQL Server instances.

    .DESCRIPTION
        Collects detailed system specifications including processor details, memory configuration, domain membership, and hardware information from target computers. This function is essential for SQL Server capacity planning, pre-installation system verification, and troubleshooting performance issues by providing complete hardware inventory data.

        The function queries WMI classes (Win32_ComputerSystem and Win32_Processor) to gather CPU details, determines hyperthreading status, checks total physical memory, and identifies domain roles. It also detects pending reboots that could affect SQL Server operations and optionally retrieves AWS EC2 metadata for cloud-hosted instances.

        Use this command when documenting SQL Server environments, verifying system requirements before installations or upgrades, or investigating hardware-related performance bottlenecks.

    .PARAMETER ComputerName
        Specifies the target computer(s) to collect system information from. Defaults to the local computer when not specified.
        Use this to inventory multiple SQL Server hosts at once or to gather system details from remote servers for capacity planning and troubleshooting.

    .PARAMETER Credential
        Alternate credential object to use for accessing the target computer(s).

    .PARAMETER IncludeAws
        Retrieves additional AWS EC2 metadata when the target computer is hosted on Amazon Web Services. Adds properties like AMI ID, instance type, availability zone, and IAM role information.
        Use this switch when documenting cloud-hosted SQL Server environments or when you need AWS-specific details for compliance or cost management purposes.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per computer specified, containing hardware and system information collected from WMI.

        Default display properties (via Select-DefaultView):
        - ComputerName: The resolved computer name
        - Domain: The domain name the computer belongs to
        - DomainRole: Role of the computer (Standalone Workstation, Member Workstation, Standalone Server, Member Server, Backup Domain Controller, or Primary Domain Controller)
        - Manufacturer: Hardware manufacturer name
        - Model: Hardware model name
        - SystemFamily: System family classification
        - SystemType: System type (e.g., "x64-based PC")
        - ProcessorName: Processor name from Win32_Processor
        - ProcessorCaption: Processor description from Win32_Processor
        - ProcessorMaxClockSpeed: Maximum processor speed in MHz
        - NumberLogicalProcessors: Number of logical processors (includes hyperthreading virtual cores)
        - NumberProcessors: Number of physical processor sockets
        - IsHyperThreading: Boolean indicating if hyperthreading is detected (logical processors > physical processors)
        - TotalPhysicalMemory: Total physical memory as a DbaSize object (shows human-readable format)
        - IsSystemManagedPageFile: Boolean indicating if Windows manages the page file automatically
        - PendingReboot: Boolean indicating if the system has a pending reboot, or $null if reboot status could not be determined

        Additional properties available but not shown by default:
        - SystemSkuNumber: System SKU number from hardware
        - IsDaylightSavingsTime: Boolean indicating if daylight saving time is enabled on the system
        - DaylightInEffect: Boolean indicating if daylight saving time is currently in effect
        - DnsHostName: DNS host name of the computer
        - AdminPasswordStatus: Administrator password status (Disabled, Enabled, Not Implemented, or Unknown)

        When -IncludeAws is specified and the computer is detected as an AWS EC2 instance, the following properties are added:
        - AwsAmiId: The AMI (Amazon Machine Image) ID
        - AwsIamRoleArn: The IAM instance profile ARN
        - AwsEc2InstanceId: The EC2 instance ID
        - AwsEc2InstanceType: The EC2 instance type (e.g., t2.large, m5.xlarge)
        - AwsAvailabilityZone: The AWS availability zone where the instance is located
        - AwsPublicHostName: The public hostname assigned to the EC2 instance

    .NOTES
        Tags: Management, Computer, OS
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaComputerSystem

    .EXAMPLE
        PS C:\> Get-DbaComputerSystem

        Returns information about the local computer's computer system

    .EXAMPLE
        PS C:\> Get-DbaComputerSystem -ComputerName sql2016

        Returns information about the sql2016's computer system

    .EXAMPLE
        PS C:\> Get-DbaComputerSystem -ComputerName sql2016 -IncludeAws

        Returns information about the sql2016's computer system and includes additional properties around the EC2 instance.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$IncludeAws,
        [switch]$EnableException
    )
    process {
        foreach ($computer in $ComputerName) {
            try {
                $server = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential

                $computerResolved = $server.FullComputerName

                if (!$computerResolved) {
                    Stop-Function -Message "Unable to resolve hostname of $computer. Skipping." -Continue
                }

                if (Test-Bound "Credential") {
                    $computerSystem = Get-DbaCmObject -ClassName Win32_ComputerSystem -ComputerName $computerResolved -Credential $Credential
                    $computerProcessor = Get-DbaCmObject -ClassName Win32_Processor -ComputerName $computerResolved -Credential $Credential
                } else {
                    $computerSystem = Get-DbaCmObject -ClassName Win32_ComputerSystem -ComputerName $computerResolved
                    $computerProcessor = Get-DbaCmObject -ClassName Win32_Processor -ComputerName $computerResolved
                }

                $adminPasswordStatus =
                switch ($computerSystem.AdminPasswordStatus) {
                    0 { "Disabled" }
                    1 { "Enabled" }
                    2 { "Not Implemented" }
                    3 { "Unknown" }
                    default { "Unknown" }
                }

                $domainRole =
                switch ($computerSystem.DomainRole) {
                    0 { "Standalone Workstation" }
                    1 { "Member Workstation" }
                    2 { "Standalone Server" }
                    3 { "Member Server" }
                    4 { "Backup Domain Controller" }
                    5 { "Primary Domain Controller" }
                }

                $isHyperThreading = $false
                if ($computerSystem.NumberOfLogicalProcessors -gt $computerSystem.NumberofProcessors) {
                    $isHyperThreading = $true
                }

                if ($IncludeAws) {
                    try {
                        $ProxiedFunc = "function Invoke-TlsRestMethod {`n" + $(Get-Item function:\Invoke-TlsRestMethod).ScriptBlock + "`n}"
                        $isAws = Invoke-Command2 -ComputerName $computerResolved -Credential $Credential -ArgumentList $ProxiedFunc -ScriptBlock {
                            Param( $ProxiedFunc )
                            . ([ScriptBlock]::Create($ProxiedFunc))
                            ((Invoke-TlsRestMethod -TimeoutSec 15 -Uri 'http://169.254.169.254').StatusCode) -eq 200
                        } -Raw
                    } catch [System.Net.WebException] {
                        $isAws = $false
                        Write-Message -Level Warning -Message "$computerResolved was not found to be an EC2 instance. Verify http://169.254.169.254 is accessible on the computer."
                    }

                    if ($isAws) {
                        $ProxiedFunc = "function Invoke-TlsRestMethod {`n" + $(Get-Item function:\Invoke-TlsRestMethod).ScriptBlock + "`n}"
                        $scriptBlock = {
                            Param( $ProxiedFunc )
                            . ([ScriptBlock]::Create($ProxiedFunc))
                            [PSCustomObject]@{
                                AmiId            = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/ami-id')
                                IamRoleArn       = ((Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/iam/info').InstanceProfileArn)
                                InstanceId       = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-id')
                                InstanceType     = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-type')
                                AvailabilityZone = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/placement/availability-zone')
                                PublicHostname   = (Invoke-TlsRestMethod -Uri 'http://169.254.169.254/latest/meta-data/public-hostname')
                            }
                        }
                        $awsProps = Invoke-Command2 -ComputerName $computerResolved -Credential $Credential -ArgumentList $ProxiedFunc -ScriptBlock $scriptBlock
                    }
                }

                $pendingReboot = $null
                try {
                    Write-Message -Level Verbose -Message "Getting information about pending reboots."
                    $pendingReboot = Test-PendingReboot -ComputerName $computerResolved -Credential $Credential
                } catch {
                    Write-Message -Level Verbose -Message "Not able to get information about pending reboots."
                }

                $inputObject = [PSCustomObject]@{
                    ComputerName            = $computerResolved
                    Domain                  = $computerSystem.Domain
                    DomainRole              = $domainRole
                    Manufacturer            = $computerSystem.Manufacturer
                    Model                   = $computerSystem.Model
                    SystemFamily            = $computerSystem.SystemFamily
                    SystemSkuNumber         = $computerSystem.SystemSKUNumber
                    SystemType              = $computerSystem.SystemType
                    ProcessorName           = $computerProcessor.Name
                    ProcessorCaption        = $computerProcessor.Caption
                    ProcessorMaxClockSpeed  = $computerProcessor.MaxClockSpeed
                    NumberLogicalProcessors = $computerSystem.NumberOfLogicalProcessors
                    NumberProcessors        = $computerSystem.NumberOfProcessors
                    IsHyperThreading        = $isHyperThreading
                    TotalPhysicalMemory     = [DbaSize]$computerSystem.TotalPhysicalMemory
                    IsDaylightSavingsTime   = $computerSystem.EnableDaylightSavingsTime
                    DaylightInEffect        = $computerSystem.DaylightInEffect
                    DnsHostName             = $computerSystem.DNSHostName
                    IsSystemManagedPageFile = $computerSystem.AutomaticManagedPagefile
                    AdminPasswordStatus     = $adminPasswordStatus
                    PendingReboot           = $pendingReboot
                }
                if ($IncludeAws -and $isAws) {
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsAmiId -Value $awsProps.AmiId
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsIamRoleArn -Value $awsProps.IamRoleArn
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsEc2InstanceId -Value $awsProps.InstanceId
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsEc2InstanceType -Value $awsProps.InstanceType
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsAvailabilityZone -Value $awsProps.AvailabilityZone
                    Add-Member -Force -InputObject $inputObject -MemberType NoteProperty -Name AwsPublicHostName -Value $awsProps.PublicHostname
                }
                $excludes = 'SystemSkuNumber', 'IsDaylightSavingsTime', 'DaylightInEffect', 'DnsHostName', 'AdminPasswordStatus'
                Select-DefaultView -InputObject $inputObject -ExcludeProperty $excludes
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}