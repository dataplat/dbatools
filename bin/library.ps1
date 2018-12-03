# Current library Version the module expects
$currentLibraryVersion = New-Object System.Version(0, 10, 0, 70)

<#
Library Versioning 101:
The version consists of 4 segments: Major, Minor, Build, Revision

Major: Should always be equal to the main version number of the dbatools PowerShell project.
Minor: Tracks major features within a major release. Increment on new features or significant structural changes. Reset to 0 when incrementing the major version.
Build: Tracks lesser functionality upgrades. Increment on all minor upgrades, reset to 0 when introducing a new major feature or major version.
Revision: Tracks all changes. Every single update to the library - bugfix, feature or redesign - increments the revision counter. It is never reset to 0.

Updating the library version number:
When changing the library version number, it is necessary to do so in TWO places:
- At the top of this very library.ps1
- Within AssemblyInfo.cs
These two locations MUST have matching version numbers, otherwise it will keep building the library and complaining about version mismatch!
#>

<#
#---------------------------------#
# Runtime configuration variables #
#---------------------------------#

The library recognizes a few external variables in order to customize its behavior on import.

$dbatools_strictsecuritymode
Setting this to $true will cause dbatools to always load the library directly from the module directory.
This is more secure, but less convenient when it comes to updating the module, as all consoles using it must be closed.

$dbatools_alwaysbuildlibrary
Setting this to $true will cause the module to always build the library from source, rather than reuse the binaries.
Mostly for developers working on the library.

#>

#region Test whether the module had already been imported
if (([System.Management.Automation.PSTypeName]'Sqlcollaborative.Dbatools.Configuration.Config').Type) {
    # No need to load the library again, if the module was once already imported.
    Write-Verbose -Message "Library already loaded, will not load again"
    $ImportLibrary = $false
} else {
    Write-Verbose -Message "Library not present already, will import"
    $ImportLibrary = $true
}
#endregion Test whether the module had already been imported

$libraryBase = (Resolve-Path -Path ($ExecutionContext.SessionState.Module.ModuleBase + "\bin"))

if ($PSVersionTable.PSVersion.Major -ge 6) {
    $dll = (Resolve-Path -Path "$libraryBase\netcoreapp2.1\dbatools.dll" -ErrorAction Ignore)
} else {
    $dll = (Resolve-Path -Path "$libraryBase\net452\dbatools.dll" -ErrorAction Ignore)
}

if ($ImportLibrary) {
    #region Add Code
    try {
        # In strict security mode, only load from the already pre-compiled binary within the module
        if ($script:strictSecurityMode) {
            if (Test-Path -Path $dll) {
                Add-Type -Path $dll -ErrorAction Stop
            } else {
                throw "Library not found, terminating!"
            }
        }
        # Else we prioritize user convenience
else {
            try {
                $sln = (Resolve-Path -Path "$libraryBase\projects\dbatools\dbatools.sln" -ErrorAction Stop)
                $hasProject = Test-Path -Path $sln -ErrorAction Stop
            } catch {
                $null = 1
            }
            
            if (-not $dll) {
                $hasCompiledDll = $false
            } else {
                $hasCompiledDll = Test-Path -Path $dll -ErrorAction Stop
            }
            
            $reslibdll = Resolve-Path -Path "$libraryBase\dbatools.dll"
            
            if ((-not $script:alwaysBuildLibrary) -and $hasCompiledDll -and ([System.Diagnostics.FileVersionInfo]::GetVersionInfo($reslibdll).FileVersion -eq $currentLibraryVersion)) {
                $start = Get-Date
                
                try {
                    $libraryBase = Resolve-Path -Path "$libraryBase\"
                    $script:DllRoot = Resolve-Path -Path $script:DllRoot
                    Write-Verbose -Message "Found library, trying to copy & import"
                    # this looks excessive but for some reason the explicit string to string is required
                    if (("$($dll)" -ne "$(Join-Path -Path $script:DllRoot -ChildPath dbatools.dll)") -and $script:isWindows) {
                        Copy-Item -Path $dll -Destination $script:DllRoot -Force -ErrorAction Stop
                    }
                    Add-Type -Path (Resolve-Path -Path "$script:DllRoot\dbatools.dll") -ErrorAction Stop
                } catch {
                    Write-Verbose -Message "Failed to copy and import, attempting to import straight from the module directory"
                    Add-Type -Path $dll -ErrorAction Stop
                }
                Write-Verbose -Message "Total duration: $((Get-Date) - $start)"
            } elseif ($hasProject) {
                . Import-ModuleFile (Resolve-Path -Path "$($script:PSModuleRoot)\bin\build-project.ps1")
            } else {
                throw "No valid dbatools library found! Check your module integrity"
            }
        }
        
        #region PowerShell TypeData
        Update-TypeData -TypeName "Sqlcollaborative.Dbatools.dbaSystem.DbatoolsException" -SerializationDepth 2 -ErrorAction Ignore
        Update-TypeData -TypeName "Sqlcollaborative.Dbatools.dbaSystem.DbatoolsExceptionRecord" -SerializationDepth 2 -ErrorAction Ignore
        #endregion PowerShell TypeData
    } catch {
        #region Warning
        Write-Verbose @'
Dear User,

in the name of the dbatools team I apologize for the inconvenience.
Generally, when something goes wrong we try to handle and interpret in an
understandable manner. Unfortunately, something went awry with importing
our main library, so all the systems making this possible would not be initialized
yet. We have taken great pains to avoid this issue but this notification indicates
we have failed.

Please, in order to help us prevent this from happening again, visit us at:
https://github.com/sqlcollaborative/dbatools/issues
and tell us about this failure. All information will be appreciated, but
especially valuable are:
- Exports of the exception: $Error | Export-Clixml error.xml -Depth 4
- Screenshots
- Environment information (Operating System, Hardware Stats, .NET Version,
  PowerShell Version and whatever else you may consider of potential impact.)

Again, I apologize for the inconvenience and hope we will be able to speedily
resolve the issue.

Best Regards,
Friedrich Weinmann
aka "The guy who made most of The Library that Failed to import"

'@
        throw
        #endregion Warning
    }
    #endregion Add Code
}

#region Version Warning
if ($currentLibraryVersion -ne ([version](([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object ManifestModule -like "dbatools.dll").CustomAttributes | Where-Object AttributeType -like "System.Reflection.AssemblyFileVersionAttribute").ConstructorArguments.Value)) {
    Write-Verbose @"
A version missmatch between the dbatools library loaded and the one expected by
this module. This usually happens when you update the dbatools module and use
Remove-Module / Import-Module in order to load the latest version without
starting a new PowerShell instance.

Please restart the console to apply the library update, or unexpected behavior will likely occur.

If the issues continue to persist, please Remove-Item '$script:PSModuleRoot\bin\dbatools.dll'
"@
}
#endregion Version Warning