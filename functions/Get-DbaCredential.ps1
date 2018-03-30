#ValidationTags#Messaging,FlowControl,CodeStyle#
function Get-DbaCredential {
    <#
        .SYNOPSIS
            Gets SQL Credential information for each instance(s) of SQL Server.

        .DESCRIPTION
            The Get-DbaCredential command gets SQL Credential information for each instance(s) of SQL Server.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Name
            Only include specific names
            Note: if spaces exist in the credential name, you will have to type "" or '' around it.

        .PARAMETER ExcludeName
            Excluded credential names
    
        .PARAMETER Identity
            Only include specific identities
            Note: if spaces exist in the credential identity, you will have to type "" or '' around it.

        .PARAMETER ExcludeIdentity
            Excluded identities

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Credential
            Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaCredential

        .EXAMPLE
            Get-DbaCredential -SqlInstance localhost

            Returns all SQL Credentials on the local default SQL Server instance

        .EXAMPLE
            Get-DbaCredential -SqlInstance localhost, sql2016 -Name 'PowerShell Proxy'

            Returns the SQL Credentials named 'PowerShell Proxy' for the local and sql2016 SQL Server instances
    
        .EXAMPLE
            Get-DbaCredential -SqlInstance localhost, sql2016 -Identity ad\powershell

            Returns the SQL Credentials for the account 'ad\powershell' on the local and sql2016 SQL Server instances
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$ExcludeName,
        [Alias('CredentialIdentity')]
        [string[]]$Identity,
        [Alias('ExcludeCredentialIdentity')]
        [string[]]$ExcludeIdentity,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $credential = $server.Credentials
            
            if ($Name) {
                $credential = $credential | Where-Object { $Name -contains $_.Name }
            }
            
            if ($ExcludeName) {
                $credential = $credential | Where-Object { $ExcludeName -notcontains $_.Name }
            }
            
            if ($Identity) {
                $credential = $credential | Where-Object { $Identity -contains $_.Identity }
            }
            
            if ($ExcludeIdentity) {
                $credential = $credential | Where-Object { $ExcludeIdentity -notcontains $_.Identity }
            }
            
            foreach ($currentcredential in $credential) {
                Add-Member -Force -InputObject $currentcredential -MemberType NoteProperty -Name ComputerName -value $currentcredential.Parent.NetName
                Add-Member -Force -InputObject $currentcredential -MemberType NoteProperty -Name InstanceName -value $currentcredential.Parent.ServiceName
                Add-Member -Force -InputObject $currentcredential -MemberType NoteProperty -Name SqlInstance -value $currentcredential.Parent.DomainInstanceName

                Select-DefaultView -InputObject $currentcredential -Property ComputerName, InstanceName, SqlInstance, ID, Name, Identity, MappedClassType, ProviderName
            }
        }
    }
}