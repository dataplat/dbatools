function Get-SQLServerVersion {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,
        [bool]$EnableException
    )
    begin {
    }
    process {
        $versions = @()
        try {
            $sqlComponents = Get-SQLInstanceComponent -ComputerName $ComputerName
            foreach ($component in $sqlComponents) {
                #Replace first decimal of the minor build with a 0, since we're using build numbers here
                #Refer to https://sqlserverbuilds.blogspot.com/
                Write-Message -Level Debug -Message "Converting version $($component.Version) to [version]"
                $newVersion = New-Object -TypeName System.Version -ArgumentList ([string]$component.Version)
                $newVersion = New-Object -TypeName System.Version -ArgumentList ($newVersion.Major , ($newVersion.Minor - $newVersion.Minor % 10), $newVersion.Build)
                Write-Message -Level Debug -Message "Converted version $($component.Version) to $newVersion"
                $currentVersion = Get-DbaBuildReference -Build $newVersion
                $versions += $currentVersion | Add-Member -Name 'Edition' -MemberType NoteProperty -Value $component.Edition -PassThru
            }
        } catch {
            Stop-Function -Message "Failed to process SQL versions" -ErrorRecord $_
            return
        }
    }
    end {
        $versions
    }
}