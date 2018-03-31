function Update-DbaSqlServiceAccount {
    <#
    .SYNOPSIS
    Changes service account (or just its password) of the SQL Server service.

    .DESCRIPTION
    Reconfigures service account or updates password of the specified SQL Server service. The service will be restarted in the event of changing the account.

    .PARAMETER ComputerName
    The SQL Server (or server in general) that you're connecting to. This command handles named instances.

    .PARAMETER Credential
    Windows Credential with permission to log on to the server running the SQL instance

    .PARAMETER InputObject
    A collection of services. Basically, any object that has ComputerName and ServiceName properties. Can be piped from Get-DbaSqlService.

    .PARAMETER ServiceName
    A name of the service on which the action is performed. E.g. MSSQLSERVER or SqlAgent$INSTANCENAME

    .PARAMETER ServiceCredential
    Windows Credential object under which the service will be setup to run. Cannot be used with -Username. For local service accounts use one of the following usernames with empty password:
    LOCALSERVICE
    NETWORKSERVICE
    LOCALSYSTEM

    .PARAMETER OldPassword
    An old password of the service account. Optional when run under local admin privileges.

    .PARAMETER NewPassword
    New password of the service account. The function will ask for a password if not specified. MSAs and local system accounts will ignore the password.

    .PARAMETER Username
    Username of the service account. Cannot be used with -ServiceCredential. For local service accounts use one of the following usernames omitting the -Password parameter:
    LOCALSERVICE
    NETWORKSERVICE
    LOCALSYSTEM

    .PARAMETER WhatIf
    Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
    Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Author: Kirill Kravtsov (@nvarscar)
    Tags:
    dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
    Copyright (C) 2017 Chrissy LeMaire
    License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
    $NewPassword = ConvertTo-SecureString 'Qwerty1234' -AsPlainText -Force
    Update-DbaSqlServiceAccount -ComputerName sql1 -ServiceName 'MSSQL$MYINSTANCE' -Password $NewPassword

    Changes the current service account's password of the service MSSQL$MYINSTANCE to 'Qwerty1234'

    .EXAMPLE
    $cred = Get-Credential
    Get-DbaSqlService sql1 -Type Engine,Agent -Instance MYINSTANCE | Update-DbaSqlServiceAccount -ServiceCredential $cred

    Requests credentials from the user and configures them as a service account for the SQL Server engine and agent services of the instance sql1\MYINSTANCE

    .EXAMPLE
    Update-DbaSqlServiceAccount -ComputerName sql1,sql2 -ServiceName 'MSSQLSERVER','SQLSERVERAGENT' -Username NETWORKSERVICE

    Configures SQL Server engine and agent services on the machines sql1 and sql2 to run under Network Service system user.

    .EXAMPLE
    Get-DbaSqlService sql1 -Type Engine -Instance MSSQLSERVER | Update-DbaSqlServiceAccount -Username 'MyDomain\sqluser1'

    Configures SQL Server engine service on the machine sql1 to run under 'MyDomain\sqluser1'. Will request user to input the account password.

    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "ServiceName" )]
    param (
        [parameter(ParameterSetName = "ServiceName")]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "InputObject")]
        [Alias("ServiceCollection")]
        [object[]]$InputObject,
        [parameter(ParameterSetName = "ServiceName", Position = 1, Mandatory = $true)]
        [Alias("Name", "Service")]
        [string[]]$ServiceName,
        [Alias("User")]
        [string]$Username,
        [PSCredential]$ServiceCredential,
        [securestring]$OldPassword = (New-Object System.Security.SecureString),
        [Alias("Password")]
        [securestring]$NewPassword = (New-Object System.Security.SecureString),
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        $svcCollection = @()
        $scriptAccountChange = {
            $service = $wmi.Services[$args[0]]
            $service.SetServiceAccount($args[1], $args[2])
            $service.Alter()
        }
        $scriptPasswordChange = {
            $service = $wmi.Services[$args[0]]
            $service.ChangePassword($args[1], $args[2])
            $service.Alter()
        }
        #Check parameters
        if ($Username) {
            $actionType = 'Account'
            if ($ServiceCredential) {
                Stop-Function -EnableException $EnableException -Message "You cannot specify both -UserName and -ServiceCredential parameters" -Category InvalidArgument
                return
            }
            #System logins should not have a domain name, whitespaces or passwords
            $trimmedUsername = (Split-Path $Username -Leaf).Trim().Replace(' ', '')
            #Request password input if password was not specified and account is not MSA or system login
            if ($NewPassword.Length -eq 0 -and $PSBoundParameters.Keys -notcontains 'NewPassword' -and $trimmedUsername -notin 'NETWORKSERVICE', 'LOCALSYSTEM', 'LOCALSERVICE' -and $Username.EndsWith('$') -eq $false -and $Username.StartsWith('NT Service\') -eq $false) {
                $NewPassword = Read-Host -Prompt "Input new password for account $UserName" -AsSecureString
                $NewPassword2 = Read-Host -Prompt "Repeat password" -AsSecureString
                if ((New-Object System.Management.Automation.PSCredential ("user", $NewPassword)).GetNetworkCredential().Password -ne `
                    (New-Object System.Management.Automation.PSCredential ("user", $NewPassword2)).GetNetworkCredential().Password) {
                    Stop-Function -Message "Passwords do not match" -Category InvalidArgument -EnableException $EnableException
                    return
                }
            }
            $currentCredential = New-Object System.Management.Automation.PSCredential ($Username, $NewPassword)
        }
        elseif ($ServiceCredential) {
            $actionType = 'Account'
            $currentCredential = $ServiceCredential
        }
        else {
            $actionType = 'Password'
        }
        if ($actionType -eq 'Account') {
            #System logins should not have a domain name, whitespaces or passwords
            $credUserName = (Split-Path $currentCredential.UserName -Leaf).Trim().Replace(' ', '')
            #Check for system logins and replace the Credential object to simplify passing localsystem-like login names
            if ($credUserName -in 'NETWORKSERVICE', 'LOCALSYSTEM', 'LOCALSERVICE') {
                $currentCredential = New-Object System.Management.Automation.PSCredential ($credUserName, (New-Object System.Security.SecureString))
            }
        }
    }
    process {
        if ($PsCmdlet.ParameterSetName -match 'ServiceName') {
            foreach ($Computer in $ComputerName.ComputerName) {
                $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
                if ($Server.ComputerName) {
                    foreach ($service in $ServiceName) {
                        $svcCollection += [psobject]@{
                            ComputerName = $server.ComputerName
                            ServiceName  = $service
                        }
                    }
                }
                else {
                    Stop-Function -EnableException $EnableException -Message "Failed to connect to $Computer" -Continue
                }
            }
        }
        elseif ($PsCmdlet.ParameterSetName -match 'InputObject') {
            foreach ($service in $InputObject) {
                $Server = Resolve-DbaNetworkName -ComputerName $service.ComputerName -Credential $credential
                if ($Server.ComputerName) {
                    $svcCollection += [psobject]@{
                        ComputerName = $Server.ComputerName
                        ServiceName  = $service.ServiceName
                    }
                }
                else {
                    Stop-Function -EnableException $EnableException -Message "Failed to connect to $($service.ComputerName)" -Continue
                }
            }
        }

    }
    end {
        foreach ($svc in $svcCollection) {
            if ($serviceObject = Get-DbaSqlService -ComputerName $svc.ComputerName -ServiceName $svc.ServiceName -Credential $Credential -EnableException:$EnableException) {
                $outMessage = $outStatus = $agent = $null
                if ($actionType -eq 'Password' -and $NewPassword.Length -eq 0) {
                    $currentPassword = Read-Host -Prompt "New password for $($serviceObject.StartName) ($($svc.ServiceName) on $($svc.ComputerName))" -AsSecureString
                    $currentPassword2 = Read-Host -Prompt "Repeat password" -AsSecureString
                    if ((New-Object System.Management.Automation.PSCredential ("user", $currentPassword)).GetNetworkCredential().Password -ne `
                        (New-Object System.Management.Automation.PSCredential ("user", $currentPassword2)).GetNetworkCredential().Password) {
                        Stop-Function -Message "Passwords do not match. This service will not be updated" -Category InvalidArgument -EnableException $EnableException -Continue
                    }
                }
                else {
                    $currentPassword = $NewPassword
                }
                if ($serviceObject.ServiceType -eq 'Engine') {
                    #Get SQL Agent running status
                    $agent = Get-DbaSqlService -ComputerName $svc.ComputerName -Type Agent -InstanceName $serviceObject.InstanceName
                }
                if ($PsCmdlet.ShouldProcess($serviceObject, "Changing account information for service $($svc.ServiceName) on $($svc.ComputerName)")) {
                    try {
                        if ($actionType -eq 'Account') {
                            Write-Message -Level Verbose -Message "Attempting an account change for service $($svc.ServiceName) on $($svc.ComputerName)"
                            $null = Invoke-ManagedComputerCommand -ComputerName $svc.ComputerName -Credential $Credential -ScriptBlock $scriptAccountChange -ArgumentList @($svc.ServiceName, $currentCredential.UserName, $currentCredential.GetNetworkCredential().Password) -EnableException:$EnableException
                            $outMessage = "The login account for the service has been successfully set."
                        }
                        elseif ($actionType -eq 'Password') {
                            Write-Message -Level Verbose -Message "Attempting a password change for service $($svc.ServiceName) on $($svc.ComputerName)"
                            $null = Invoke-ManagedComputerCommand -ComputerName $svc.ComputerName -Credential $Credential -ScriptBlock $scriptPasswordChange -ArgumentList @($svc.ServiceName, (New-Object System.Management.Automation.PSCredential ("user", $OldPassword)).GetNetworkCredential().Password, (New-Object System.Management.Automation.PSCredential ("user", $currentPassword)).GetNetworkCredential().Password) -EnableException:$EnableException
                            $outMessage = "The password has been successfully changed."
                        }
                        $outStatus = 'Successful'
                    }
                    catch {
                        $outStatus = 'Failed'
                        $outMessage = $_.Exception.Message
                        Write-Message -Level Warning -Message $_.Exception.Message -EnableException $EnableException
                    }
                }
                else {
                    $outStatus = 'Successful'
                    $outMessage = 'No changes made - running in -WhatIf mode.'
                }
                if ($serviceObject.ServiceType -eq 'Engine' -and $actionType -eq 'Account' -and $outStatus -eq 'Successful' -and $agent.State -eq 'Running') {
                    #Restart SQL Agent after SQL Engine has been restarted
                    if ($PsCmdlet.ShouldProcess($serviceObject, "Starting SQL Agent after Engine account change on $($svc.ComputerName)")) {
                        $res = Start-DbaSqlService -ComputerName $svc.ComputerName -Type Agent -InstanceName $serviceObject.InstanceName
                        if ($res.Status -ne 'Successful') {
                            Write-Message -Level Warning -Message "Failed to restart SQL Agent after changing credentials. $($res.Message)"
                        }
                    }
                }
                $serviceObject = Get-DbaSqlService -ComputerName $svc.ComputerName -ServiceName $svc.ServiceName -Credential $Credential -EnableException:$EnableException
                Add-Member -Force -InputObject $serviceObject -NotePropertyName Message -NotePropertyValue $outMessage
                Add-Member -Force -InputObject $serviceObject -NotePropertyName Status -NotePropertyValue $outStatus
                Select-DefaultView -InputObject $serviceObject -Property ComputerName, ServiceName, State, StartName, Status, Message
            }
            Else {
                Stop-Function -Message "The service $($svc.ServiceName) has not been found on $($svc.ComputerName)" -EnableException $EnableException -Continue
            }
        }
    }
}