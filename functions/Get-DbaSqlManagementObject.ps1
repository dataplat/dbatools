function Get-DbaSqlManagementObject {
    <#
        .SYNOPSIS
            Gets SQL Mangaement Object versions installed on the machine.

        .DESCRIPTION
            The Get-DbaSqlManagementObject returns an object with the Version and the
            Add-Type Load Template for each version on the server.

        .PARAMETER ComputerName
            The name of the target you would like to check

        .PARAMETER Credential
            This command uses Windows credentials. This parameter allows you to connect remotely as a different user.

        .PARAMETER VersionNumber
            This is the specific version number you are looking for. The function will look
            for that version only.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: SMO
            Author: Ben Miller (@DBAduck - http://dbaduck.com)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaSqlManagementObject

        .EXAMPLE
            Get-DbaSqlManagementObject

            Returns all versions of SMO on the computer

        .EXAMPLE
            Get-DbaSqlManagementObject -VersionNumber 13

            Returns just the version specified. If the version does not exist then it will return nothing.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "SqlInstance")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]
        $Credential,
        [int]$VersionNumber,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        if (!$VersionNumber) {
            $VersionNumber = 0
        }
        $scriptblock = {
            $VersionNumber = [int]$args[0]

            Write-Message -Level Verbose -Message "Checking currently loaded SMO version"
            $loadedversion = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }
            if ($loadedversion) {
                $loadedversion = $loadedversion | ForEach-Object {
                    if ($_.Location -match "__") {
                        ((Split-Path (Split-Path $_.Location) -Leaf) -split "__")[0]
                    }
                    else {
                        ((Get-ChildItem -Path $_.Location).VersionInfo.ProductVersion)
                    }
                }
            }

            Write-Message -Level Verbose -Message "Looking for included smo library"
            $localversion = [version](Get-ChildItem -Path "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Smo.dll").VersionInfo.ProductVersion

            foreach ($version in $localversion) {
                if ($VersionNumber -eq 0) {
                    Write-Message -Level Verbose -Message "Did not pass a version"
                    [PSCustomObject]@{
                        ComputerName = $env:COMPUTERNAME
                        Version      = $localversion
                        Loaded       = $loadedversion -contains $localversion
                        LoadTemplate = "Add-Type -Path $("$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Smo.dll")"
                    }
                }
                else {
                    Write-Message -Level Verbose -Message "Passed version $VersionNumber, looking for that specific version"
                    if ($localversion.ToString().StartsWith("$VersionNumber.")) {
                        Write-Message -Level Verbose -Message "Found the Version $VersionNumber"
                        [PSCustomObject]@{
                            ComputerName = $env:COMPUTERNAME
                            Version      = $localversion
                            Loaded       = $loadedversion -contains $localversion
                            LoadTemplate = "Add-Type -Path $("$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Smo.dll")"
                        }
                    }
                }
            }

            Write-Message -Level Verbose -Message "Looking for SMO in the Global Assembly Cache"
            $smolist = (Get-ChildItem -Path "$env:SystemRoot\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" | Sort-Object Name -Descending).Name

            foreach ($version in $smolist) {
                $array = $version.Split("__")
                if ($VersionNumber -eq 0) {
                    Write-Message -Level Verbose -Message "Did not pass a version, looking for all versions"
                    $currentversion = $array[0]
                    [PSCustomObject]@{
                        ComputerName = $env:COMPUTERNAME
                        Version      = $currentversion
                        Loaded       = $loadedversion -contains $currentversion
                        LoadTemplate = "Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=$($array[0]), Culture=neutral, PublicKeyToken=89845dcd8080cc91`""
                    }
                }
                else {
                    Write-Message -Level Verbose -Message "Passed version $VersionNumber, looking for that specific version"
                    if ($array[0].StartsWith("$VersionNumber.")) {
                        Write-Message -Level Verbose -Message "Found the Version $VersionNumber"
                        $currentversion = $array[0]
                        [PSCustomObject]@{
                            ComputerName = $env:COMPUTERNAME
                            Version      = $currentversion
                            Loaded       = $loadedversion -contains $currentversion
                            LoadTemplate = "Add-Type -AssemblyName `"Microsoft.SqlServer.Smo, Version=$($array[0]), Culture=neutral, PublicKeyToken=89845dcd8080cc91`""
                        }
                    }
                }
            }
        }
    }

    process {
        foreach ($computer in $ComputerName.ComputerName) {
            try {
                Invoke-Command2 -ComputerName $computer -ScriptBlock $scriptblock -Credential $Credential -ArgumentList $VersionNumber -ErrorAction Stop
            }
            catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $ComputerName
            }
        }
    }
}