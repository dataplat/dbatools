function New-DbaAgentProxy {
    <#
    .SYNOPSIS
        Adds one or more proxies to SQL Server Agent

    .DESCRIPTION
        Adds one or more proxies to SQL Server Agent

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The name of the proxy or proxies you want to create

    .PARAMETER ProxyCredential
        The associated SQL Server Credential. The credential must be created prior to creating the Proxy.

    .PARAMETER SubSystem
        The associated subsystem or subsystems. Defaults to CmdExec.

        Valid options include:
        ActiveScripting
        AnalysisCommand
        AnalysisQuery
        CmdExec
        Distribution
        LogReader
        Merge
        PowerShell
        QueueReader
        Snapshot
        Ssis
        TransactSql

    .PARAMETER Description
        A description of the proxy

    .PARAMETER Login
        The SQL Server login or logins (known as proxy principals) to assign to the proxy

    .PARAMETER ServerRole
        The SQL Server role or roles (known as proxy principals) to assign to the proxy

    .PARAMETER MsdbRole
        The msdb role or roles (known as proxy principals) to assign to the proxy

    .PARAMETER Disabled
        Create the proxy as disabled

    .PARAMETER Force
        Drop and recreate the proxy if it already exists

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Proxy
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAgentProxy

    .EXAMPLE
        PS C:\> New-DbaAgentProxy -SqlInstance sql2016 -Name STIG -ProxyCredential 'PowerShell Proxy'

        Creates an Agent Proxy on sql2016 with the name STIG with the 'PowerShell Proxy' credential.
        The proxy is automatically added to the CmdExec subsystem.

    .EXAMPLE
        PS C:\> New-DbaAgentProxy -SqlInstance localhost\sql2016 -Name STIG -ProxyCredential 'PowerShell Proxy' -Description "Used for auditing purposes" -Login ad\sqlstig -SubSystem CmdExec, PowerShell -ServerRole securtyadmin -MsdbRole ServerGroupAdministratorRole

        Creates an Agent Proxy on sql2016 with the name STIG with the 'PowerShell Proxy' credential and the following principals:

        Login: ad\sqlstig
        ServerRole: securtyadmin
        MsdbRole: ServerGroupAdministratorRole

        By default, only sysadmins have access to create job steps with proxies. This will allow 3 additional principals access:
        The proxy is then added to the CmdExec and PowerShell subsystems

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameter ProxyCredential")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string[]]$Name,
        [parameter(Mandatory)]
        [string[]]$ProxyCredential,
        [ValidateSet("ActiveScripting", "AnalysisCommand", "AnalysisQuery", "CmdExec", "Distribution", "LogReader", "Merge", "PowerShell", "QueueReader", "Snapshot", "Ssis", "TransactSql")]
        [string[]]$SubSystem = "CmdExec",
        [string]$Description,
        [string[]]$Login,
        [string[]]$ServerRole,
        [string[]]$MsdbRole,
        [switch]$Disabled,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $jobServer = $server.JobServer
            } catch {
                Stop-Function -Message "Failure. Is SQL Agent started?" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($proxyname in $name) {

                if ($jobServer.ProxyAccounts[$proxyName]) {
                    if ($force) {
                        if ($Pscmdlet.ShouldProcess($instance, "Dropping $proxyname")) {
                            $jobServer.ProxyAccounts[$proxyName].Drop()
                            $jobServer.ProxyAccounts.Refresh()
                        }
                    } else {
                        Write-Message -Level Warning -Message "Proxy account $proxy already exists on $instance. Use -Force to drop and recreate."
                        continue
                    }
                }

                if (-not $server.Credentials[$ProxyCredential]) {
                    Write-Message -Level Warning -Message "Credential '$ProxyCredential' does not exist on $instance"
                    continue
                }

                if ($Pscmdlet.ShouldProcess($instance, "Adding $proxyname with the $ProxyCredential credential")) {
                    # the new-object is stubborn and $true/$false has to be forced in
                    switch (Test-Bound -ParameterName Disabled) {
                        $false {
                            $proxy = New-Object Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount -ArgumentList $jobServer, $ProxyName, $ProxyCredential, $true, $Description
                        }
                        $true {
                            $proxy = New-Object Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount -ArgumentList $jobServer, $ProxyName, $ProxyCredential, $false, $Description
                        }
                    }

                    try {
                        $proxy.Create()
                    } catch {
                        Stop-Function -Message "Could not create proxy account" -ErrorRecord $_ -Target $instance -Continue
                    }
                }

                foreach ($loginname in $login) {
                    if ($server.Logins[$loginname]) {
                        if ($Pscmdlet.ShouldProcess($instance, "Adding login $loginname to proxy")) {
                            $proxy.AddLogin($loginname)
                        }
                    } else {
                        Write-Message -Level Warning -Message "Login '$loginname' does not exist on $instance"
                    }
                }

                foreach ($role in $ServerRole) {
                    if ($server.Roles[$role]) {
                        if ($Pscmdlet.ShouldProcess($instance, "Adding server role $role to proxy")) {
                            $proxy.AddServerRole($role)
                        }
                    } else {
                        Write-Message -Level Warning -Message "Server Role '$role' does not exist on $instance"
                    }
                }

                foreach ($role in $MsdbRole) {
                    if ($server.Databases['msdb'].Roles[$role]) {
                        if ($Pscmdlet.ShouldProcess($instance, "Adding msdb role $role to proxy")) {
                            $proxy.AddMsdbRole($role)
                        }
                    } else {
                        Write-Message -Level Warning -Message "msdb role '$role' does not exist on $instance"
                    }
                }

                foreach ($system in $SubSystem) {
                    if ($Pscmdlet.ShouldProcess($instance, "Adding subsystem $system to proxy")) {
                        $proxy.AddSubSystem($system)
                    }
                }

                if ($Pscmdlet.ShouldProcess("console", "Outputting Proxy object")) {
                    $proxy.Alter()
                    $proxy.Refresh()
                    Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name Logins -value $proxy.EnumLogins()
                    Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name ServerRoles -value $proxy.EnumServerRoles()
                    Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name MsdbRoles -value $proxy.EnumMsdbRoles()
                    Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name Subsystems -value $proxy.EnumSubSystems()

                    Select-DefaultView -InputObject $proxy -Property ComputerName, InstanceName, SqlInstance, ID, Name, CredentialName, CredentialIdentity, Description, Logins, ServerRoles, MsdbRoles, SubSystems, IsEnabled
                }
            }
        }
    }
}