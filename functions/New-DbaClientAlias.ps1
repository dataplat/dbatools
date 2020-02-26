function New-DbaClientAlias {
    <#
    .SYNOPSIS
        Creates/updates a sql alias for the specified server - mimics cliconfg.exe

    .DESCRIPTION
        Creates/updates a SQL Server alias by altering HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client

    .PARAMETER ComputerName
        The target computer where the alias will be created

    .PARAMETER Credential
        Allows you to login to remote computers using alternative credentials

    .PARAMETER ServerName
        The target SQL Server

    .PARAMETER Alias
        The alias to be created

    .PARAMETER Protocol
        The protocol for the connection, either TCPIP or NetBIOS. Defaults to TCPIP.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Alias
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaClientAlias

    .EXAMPLE
        PS C:\> New-DbaClientAlias -ServerName sqlcluster\sharepoint -Alias sp

        Creates a new TCP alias on the local workstation called sp, which points sqlcluster\sharepoint


    .EXAMPLE
        PS C:\> New-DbaClientAlias -ServerName 'sqlcluster,14443' -Alias spinstance

        Creates a new TCP alias on the local workstation called spinstance, which points to sqlcluster, port 14443.

    .EXAMPLE
        PS C:\> New-DbaClientAlias -ServerName sqlcluster\sharepoint -Alias sp -Protocol NamedPipes

        Creates a new NamedPipes alias on the local workstation called sp, which points sqlcluster\sharepoint

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$ServerName,
        [parameter(Mandatory)]
        [string]$Alias,
        [ValidateSet("TCPIP", "NamedPipes")]
        [string]$Protocol = "TCPIP",
        [switch]$EnableException
    )

    begin {
        # This is a script block so cannot use messaging system
        $scriptblock = {
            $basekeys = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer", "HKLM:\SOFTWARE\Microsoft\MSSQLServer"
            #Variable marked as unused by PSScriptAnalyzer
            #$ServerName = $args[0]
            $Alias = $args[1]
            $serverstring = $args[2]

            if ($env:PROCESSOR_ARCHITECTURE -like "*64*") { $64bit = $true }

            foreach ($basekey in $basekeys) {
                if ($64bit -ne $true -and $basekey -like "*WOW64*") { continue }

                $client = "$basekey\Client"

                if ((Test-Path $client) -eq $false) {
                    # "Creating $client key"
                    $null = New-Item -Path $client -Force
                }

                $connect = "$client\ConnectTo"

                if ((Test-Path $connect) -eq $false) {
                    # "Creating $connect key"
                    $null = New-Item -Path $connect -Force
                }

                <#
                #Variable marked as unused by PSScriptAnalyzer
                #Looks like it was once used for a Verbose Message
                if ($basekey -like "*WOW64*") {
                    $architecture = "32-bit"
                } else {
                    $architecture = "64-bit"
                }
                #>
                <# DO NOT use Write-Message as this is inside of a script block #>
                # Write-Verbose "Creating/updating alias for $ComputerName for $architecture"
                $null = New-ItemProperty -Path $connect -Name $Alias -Value $serverstring -PropertyType String -Force
            }
        }
    }

    process {
        if ($protocol -eq "TCPIP") {
            $serverstring = "DBMSSOCN,$ServerName"
        } else {
            $serverstring = "DBNMPNTW,\\$ServerName\pipe\sql\query"
        }

        foreach ($computer in $ComputerName.ComputerName) {

            $null = Test-ElevationRequirement -ComputerName $computer -Continue

            if ($PScmdlet.ShouldProcess($computer, "Adding $alias")) {
                try {
                    Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ErrorAction Stop -ArgumentList $ServerName, $Alias, $serverstring
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                }
            }

            Get-DbaClientAlias -ComputerName $computer -Credential $Credential | Where-Object AliasName -eq $Alias
        }
    }
}