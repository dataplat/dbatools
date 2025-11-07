function Test-DbaMLServicesInstalled {
    <#
    .SYNOPSIS
        Internal function. Tests if SQL Server Machine Learning Services (R or Python) are installed.

    .DESCRIPTION
        Checks if a SQL Server instance has Machine Learning Services (R and/or Python) installed
        by examining the installed components.

    .PARAMETER Component
        The component objects from Get-SQLInstanceComponent.

    .NOTES
        Author: the dbatools team + Claude
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Component
    )

    # Check registry for ML Services features
    # These features indicate R or Python are installed:
    # - AdvancedAnalytics (base ML Services)
    # - SQL_INST_MR (R packages in-database)
    # - SQL_INST_MPY (Python packages in-database)

    $regScript = {
        $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey("LocalMachine", "Default")
        $baseKeys = "SOFTWARE\Microsoft\Microsoft SQL Server", "SOFTWARE\Wow6432Node\Microsoft\Microsoft SQL Server"

        if ($reg.OpenSubKey($baseKeys[0])) {
            $regPath = $baseKeys[0]
        } elseif ($reg.OpenSubKey($baseKeys[1])) {
            $regPath = $baseKeys[1]
        } else {
            return $false
        }

        # Get all installed instances
        $regKey = $reg.OpenSubKey("$regPath\Instance Names\SQL")
        if (-not $regKey) {
            return $false
        }

        foreach ($instanceName in $regKey.GetValueNames()) {
            $instanceId = $regKey.GetValue($instanceName)
            $setupKey = $reg.OpenSubKey("$regPath\$instanceId\Setup")

            if ($setupKey) {
                try {
                    $featureList = $setupKey.GetValue("FeatureList")
                    if ($featureList) {
                        # Check if any ML Services features are in the feature list
                        if ($featureList -match "(AdvancedAnalytics|SQL_INST_MR|SQL_INST_MPY)") {
                            return $true
                        }
                    }
                } catch {
                    # Continue checking other instances
                }
            }
        }

        return $false
    }

    # For now, just check the component instance names to see if it's a version that could have ML
    # SQL 2016 (13.x) introduced R Services
    # SQL 2017 (14.x) introduced Python and renamed to ML Services
    $hasMLCapableVersion = $Component | Where-Object { $_.Version.NameLevel -in "2016", "2017" }

    if ($hasMLCapableVersion) {
        return $true
    }

    return $false
}
