function Find-DbaMLServicesCabFile {
    <#
    .SYNOPSIS
        Internal function. Finds SQL Server 2017 Machine Learning Services CAB files for cumulative updates.

    .DESCRIPTION
        Searches for R and Python CAB files required for SQL Server 2017 Machine Learning Services updates.
        These CAB files must be placed in the same directory as the cumulative update installer.

    .PARAMETER Path
        The path where the KB installer is located. CAB files should be in the same directory.

    .PARAMETER ComputerName
        The target computer to search on.

    .PARAMETER Credential
        Credential to use for remote connections.

    .PARAMETER Authentication
        Authentication method for remote connections.

    .NOTES
        Author: the dbatools team + Claude
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$Path,
        [DbaInstanceParameter]$ComputerName,
        [pscredential]$Credential,
        [ValidateSet("Default", "Basic", "Negotiate", "NegotiateWithImplicitCredential", "Credssp", "Digest", "Kerberos")]
        [string]$Authentication = "Default"
    )

    $cabScript = {
        Param (
            $Path
        )
        $cabFiles = New-Object System.Collections.ArrayList
        foreach ($folder in (Get-Item -Path $Path -ErrorAction SilentlyContinue)) {
            # Look for ML Services CAB files
            # R CAB files: SRO_*.cab (R Open) and SRS_*.cab (R Server)
            # Python CAB files: SPO_*.cab (Python Open) and SPS_*.cab (Python Server)
            $rCabs = Get-ChildItem -Path $folder.FullName -Filter "SR*.cab" -File -ErrorAction SilentlyContinue
            $pyCabs = Get-ChildItem -Path $folder.FullName -Filter "SP*.cab" -File -ErrorAction SilentlyContinue

            foreach ($cab in ($rCabs + $pyCabs)) {
                # Only include CAB files that match the expected patterns
                if ($cab.Name -match "^(SRO|SRS|SPO|SPS)_.*\.cab$") {
                    $null = $cabFiles.Add($cab)
                }
            }
        }
        return $cabFiles
    }

    $params = @{
        ComputerName   = $ComputerName
        Credential     = $Credential
        Authentication = $Authentication
        ScriptBlock    = $cabScript
        ArgumentList   = @($Path)
        ErrorAction    = "Stop"
        Raw            = $true
    }

    try {
        Invoke-CommandWithFallback @params
    } catch {
        Write-Message -Level Warning -Message "Failed to search for CAB files: $_"
        return $null
    }
}
