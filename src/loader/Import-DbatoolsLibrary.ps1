# Loads the dbatools library: the assembly redirectors, SqlClient, SMO and the other shared
# assemblies. dbatools.psm1 sets $script:DbatoolsLibraryRoot (the module's library folder) and
# dot-sources this file into its own scope before it imports dbatools.dll. Until dbatools 3.0 this
# was the separate dbatools.library module. An assembly another module already loaded (SMO and
# SqlClient from SqlServer, for example) is reused, never loaded a second time; finding them is one
# look at the loaded assemblies, so it always happens (2.x needed -AvoidConflicts for it).

function Get-DbatoolsLibraryPath {
    [CmdletBinding()]
    param()
    if ($PSVersionTable.PSEdition -eq "Core") {
        Join-Path -Path $script:DbatoolsLibraryRoot -ChildPath core
    } else {
        Join-Path -Path $script:DbatoolsLibraryRoot -ChildPath desktop
    }
}

$script:libraryroot = Get-DbatoolsLibraryPath

if ($PSVersionTable.PSEdition -ne "Core") {
    if (-not ("Dataplat.Dbatools.Loader.Redirector" -as [type])) {
        $source = @"
            using System;
            using System.IO;
            using System.Reflection;

            namespace Dataplat.Dbatools.Loader
            {
            public class Redirector
            {
                private static string _libPath;

                public Redirector(string libPath)
                {
                    _libPath = libPath;
                    this.EventHandler = new ResolveEventHandler(AssemblyResolve);
                }

                public static string LibPath { get { return _libPath; } }

                public readonly ResolveEventHandler EventHandler;

                private const string UnsafeName = "System.Runtime.CompilerServices.Unsafe";

                // Returns the newest loaded copy when it is at least the requested version; otherwise the shipped copy
                // when that is newer than any loaded one; otherwise the newest loaded copy, or null when none is loaded
                // and none is shipped.
                private static Assembly ResolveUnsafe(AssemblyName requestedName)
                {
                    Assembly newest = null;
                    Version newestVersion = null;
                    foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
                    {
                        try
                        {
                            var loadedName = assembly.GetName();
                            if (loadedName.Name == UnsafeName && (newestVersion == null || loadedName.Version > newestVersion))
                            {
                                newest = assembly;
                                newestVersion = loadedName.Version;
                            }
                        }
                        catch
                        {
                            // Some assemblies may throw when accessing GetName()
                        }
                    }

                    if (newest != null && (requestedName.Version == null || newestVersion >= requestedName.Version))
                    {
                        return newest;
                    }

                    string shippedPath = Path.Combine(_libPath, UnsafeName + ".dll");
                    if (File.Exists(shippedPath))
                    {
                        try
                        {
                            if (newest == null || AssemblyName.GetAssemblyName(shippedPath).Version > newestVersion)
                            {
                                return Assembly.LoadFrom(shippedPath);
                            }
                        }
                        catch
                        {
                            // Failed to read or load the shipped copy; fall back to the loaded one
                        }
                    }

                    return newest;
                }

                protected static Assembly AssemblyResolve(object sender, ResolveEventArgs e)
                {
                    var requestedName = new AssemblyName(e.Name);
                    var assemblyName = requestedName.Name;

                    // System.Runtime.CompilerServices.Unsafe: SMO asks for 4.0.4.1, while Microsoft.Identity.Client
                    // (every Microsoft Entra sign-in of Microsoft.Data.SqlClient) needs members only 6.x has, such as
                    // Unsafe.AddByteOffset(ref T, UIntPtr). 6.x keeps every 4.x member, so the shipped 6.x copy serves
                    // every request, and an older copy loaded first never answers a newer request.
                    if (assemblyName == UnsafeName)
                    {
                        var unsafeAssembly = ResolveUnsafe(requestedName);
                        if (unsafeAssembly != null)
                        {
                            return unsafeAssembly;
                        }
                    }

                    // First, check if any version of this assembly is already loaded
                    // This handles version mismatches (e.g., SMO requesting SqlClient 5.0.0.0 when 6.0.2 is loaded)
                    foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
                    {
                        try
                        {
                            if (assembly.GetName().Name == assemblyName)
                            {
                                return assembly;
                            }
                        }
                        catch
                        {
                            // Some assemblies may throw when accessing GetName()
                        }
                    }

                    // Try to load from our lib folder if the file exists
                    string dllPath = Path.Combine(_libPath, assemblyName + ".dll");
                    if (File.Exists(dllPath))
                    {
                        try
                        {
                            return Assembly.LoadFrom(dllPath);
                        }
                        catch
                        {
                            // Failed to load, return null to let default resolution continue
                        }
                    }

                    return null;
                }
            }
            }
"@

        $null = Add-Type -TypeDefinition $source
    }

    try {
        $libPath = [System.IO.Path]::Combine($script:libraryroot, "lib")
        $redirector = New-Object Dataplat.Dbatools.Loader.Redirector($libPath)
        [System.AppDomain]::CurrentDomain.add_AssemblyResolve($redirector.EventHandler)
    } catch {
        Write-Verbose "Could not register Redirector: $_"
    }
} else {
    # PowerShell Core: Use AssemblyLoadContext.Resolving event for version redirection
    # This handles version mismatches when SqlServer module loads different versions of assemblies
    # IMPORTANT: Must be implemented in C# because the resolver runs on .NET threads without PowerShell runspaces
    $dir = [System.IO.Path]::Combine($script:libraryroot, "lib") + [System.IO.Path]::DirectorySeparatorChar

    if (-not ("Dataplat.Dbatools.Loader.CoreRedirector" -as [type])) {
        $coreSourcePath = Join-Path $script:DbatoolsLibraryRoot "CoreRedirector.cs"
        $coreSource = Get-Content -Path $coreSourcePath -Raw
        try {
            $null = Add-Type -TypeDefinition $coreSource -ReferencedAssemblies 'System.Runtime.Loader','System.Runtime.InteropServices','System.Collections','System.Diagnostics.TraceSource','System.Threading'
        } catch {
            Write-Verbose "Could not compile CoreRedirector: $_"
        }
    }

    try {
        [Dataplat.Dbatools.Loader.CoreRedirector]::Register($dir)
    } catch {
        Write-Verbose "Could not register CoreRedirector: $_"
    }
}

function Get-DbatoolsSqlClientPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LibraryRoot
    )

    $libPath = [System.IO.Path]::Combine($LibraryRoot, "lib")
    if ($PSVersionTable.PSEdition -eq "Core") {
        if ($IsWindows) {
            $runtimeSqlClient = [System.IO.Path]::Combine($libPath, "runtimes", "win", "lib", "net8.0", "Microsoft.Data.SqlClient.dll")
        } else {
            $runtimeSqlClient = [System.IO.Path]::Combine($libPath, "runtimes", "unix", "lib", "net8.0", "Microsoft.Data.SqlClient.dll")
        }

        if (Test-Path $runtimeSqlClient) {
            return $runtimeSqlClient
        }
    }

    [System.IO.Path]::Combine($libPath, "Microsoft.Data.SqlClient.dll")
}

function Add-DbatoolsNativeSearchPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LibraryRoot
    )

    if ($PSVersionTable.PSEdition -ne "Core" -or -not $IsWindows) {
        return
    }

    $architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
    $nativeRid = "win-$architecture"
    $nativePath = [System.IO.Path]::Combine($LibraryRoot, "lib", "runtimes", $nativeRid, "native")
    if (-not (Test-Path $nativePath)) {
        return
    }

    $pathSeparator = [System.IO.Path]::PathSeparator
    $pathParts = $env:PATH -split [Regex]::Escape([string]$pathSeparator)
    if ($pathParts -contains $nativePath) {
        return
    }

    $env:PATH = $nativePath + $pathSeparator + $env:PATH
}

Add-DbatoolsNativeSearchPath -LibraryRoot $script:libraryroot
$sqlclient = Get-DbatoolsSqlClientPath -LibraryRoot $script:libraryroot

# Get loaded assemblies once for reuse (used for the already-loaded checks and later assembly loading)
$script:loadedAssemblies = [System.AppDomain]::CurrentDomain.GetAssemblies()

# Check for incompatible System.ClientModel or SqlClient versions
# Azure.Core 1.44+ requires System.ClientModel 1.1+ with IPersistableModel.Write() method
# SqlServer module's SqlClient 5.x includes older System.ClientModel that's incompatible
$script:hasIncompatibleClientModel = $false
# Check if System.ClientModel is already loaded with incompatible version
$existingClientModel = $script:loadedAssemblies | Where-Object { $_.GetName().Name -eq 'System.ClientModel' }
if ($existingClientModel) {
    $clientModelVersion = $existingClientModel.GetName().Version
    # System.ClientModel 1.1.0+ has the required IPersistableModel interface changes
    if ($clientModelVersion -lt [Version]'1.1.0') {
        $script:hasIncompatibleClientModel = $true
        Write-Verbose "Detected incompatible System.ClientModel version $clientModelVersion - will skip Azure.Core and Azure.Identity to avoid MissingMethodException"
    }
}

# Check if SqlServer's older SqlClient is loaded (which bundles incompatible System.ClientModel)
# SqlClient 5.x from SqlServer module uses System.ClientModel 1.0.x
# Our Azure.Core requires System.ClientModel 1.1+
if (-not $script:hasIncompatibleClientModel) {
    $existingSqlClient = $script:loadedAssemblies | Where-Object { $_.GetName().Name -eq 'Microsoft.Data.SqlClient' }
    if ($existingSqlClient) {
        $sqlClientVersion = $existingSqlClient.GetName().Version
        # SqlClient 5.x bundles older System.ClientModel; 6.x bundles compatible versions
        if ($sqlClientVersion.Major -lt 6) {
            $script:hasIncompatibleClientModel = $true
            Write-Verbose "Detected SqlClient $sqlClientVersion (pre-6.0) which uses incompatible System.ClientModel - will skip Azure.Core and Azure.Identity to avoid MissingMethodException"
        }
    }
}

# Reuse a SqlClient that is already loaded; loading a second version fails on PowerShell 7
$skipSqlClient = $false
$existingAssembly = $script:loadedAssemblies | Where-Object { $_.GetName().Name -eq 'Microsoft.Data.SqlClient' }
if ($existingAssembly) {
    $skipSqlClient = $true
    Write-Verbose "Skipping Microsoft.Data.SqlClient.dll - already loaded"
}

if (-not $skipSqlClient) {
    try {
        Import-Module $sqlclient
    } catch {
        throw "Couldn't import $sqlclient | $PSItem"
    }
}

if ($PSVersionTable.PSEdition -eq "Core") {
    $names = @(
        'Microsoft.SqlServer.Server',
        'Azure.Core',
        'Azure.Identity',
        'Microsoft.IdentityModel.Abstractions',
        'Microsoft.SqlServer.Dac',
        'Microsoft.SqlServer.Dac.Extensions',
        'Microsoft.Data.Tools.Utilities',
        'Microsoft.Data.Tools.Schema.Sql',
        'Microsoft.SqlServer.TransactSql.ScriptDom',
        'Microsoft.SqlServer.Smo',
        'Microsoft.SqlServer.SmoExtended',
        'Microsoft.SqlServer.SqlWmiManagement',
        'Microsoft.SqlServer.WmiEnum',
        'Microsoft.SqlServer.Management.RegisteredServers',
        'Microsoft.SqlServer.Management.Collector',
        'Microsoft.SqlServer.Management.XEvent',
        'Microsoft.SqlServer.Management.XEventDbScoped',
        'Microsoft.SqlServer.XEvent.XELite'
    )
} else {
    $names = @(
        'Azure.Core',
        'Azure.Identity',
        'Microsoft.IdentityModel.Abstractions',
        'Microsoft.SqlServer.Dac',
        'Microsoft.SqlServer.Dac.Extensions',
        'Microsoft.Data.Tools.Utilities',
        'Microsoft.Data.Tools.Schema.Sql',
        'Microsoft.SqlServer.TransactSql.ScriptDom',
        'Microsoft.SqlServer.Smo',
        'Microsoft.SqlServer.SmoExtended',
        'Microsoft.SqlServer.SqlWmiManagement',
        'Microsoft.SqlServer.WmiEnum',
        'Microsoft.SqlServer.Management.RegisteredServers',
        'Microsoft.SqlServer.Management.IntegrationServices',
        'Microsoft.SqlServer.Management.Collector',
        'Microsoft.SqlServer.Management.XEvent',
        'Microsoft.SqlServer.Management.XEventDbScoped',
        'Microsoft.SqlServer.XEvent.XELite'
    )
}

if ($Env:SMODefaultModuleName) {
    # then it's DSC, load other required assemblies
    $names += "Microsoft.AnalysisServices.Core"
    $names += "Microsoft.AnalysisServices"
    $names += "Microsoft.AnalysisServices.Tabular"
    $names += "Microsoft.AnalysisServices.Tabular.Json"
}

# XEvent stuff kills CI/CD
if ($PSVersionTable.OS -match "ARM64") {
    $names = $names | Where-Object { $PSItem -notmatch "XE" }
}
#endregion Names

# Build string of loaded assembly names once for efficient checking
$script:loadedAssemblyNames = $script:loadedAssemblies.FullName | Out-String

$bogusPath = [IO.Path]::Combine($script:libraryroot, "third-party", "bogus", "Bogus.dll")
try {
    $null = Import-Module $bogusPath
} catch {
    Write-Error "Could not import $bogusPath : $($_ | Out-String)"
}

foreach ($name in $names) {
    $x64only = 'Microsoft.SqlServer.Replication', 'Microsoft.SqlServer.XEvent.Linq', 'Microsoft.SqlServer.BatchParser', 'Microsoft.SqlServer.Rmo', 'Microsoft.SqlServer.BatchParserClient'

    if ($name -in $x64only -and $env:PROCESSOR_ARCHITECTURE -eq "x86") {
        Write-Verbose -Message "Skipping $name. x86 not supported for this library."
        continue
    }

    # Skip Azure.Core and Azure.Identity if System.ClientModel is incompatible
    # These assemblies depend on System.ClientModel 1.1+ which has breaking API changes
    if ($script:hasIncompatibleClientModel -and $name -in @('Azure.Core', 'Azure.Identity')) {
        Write-Verbose "Skipping $name.dll - incompatible System.ClientModel already loaded"
        continue
    }

    # Check if assembly is already loaded (always check to avoid duplicate loads)
    if ($script:loadedAssemblyNames.Contains("$name,")) {
        Write-Verbose "Skipping $name.dll - already loaded"
        continue
    }

    # Load the assembly
    $assemblyPath = [IO.Path]::Combine($script:libraryroot, "lib", "$name.dll")
    try {
        $null = Import-Module $assemblyPath
    } catch {
        Write-Error "Could not import $assemblyPath : $($_ | Out-String)"
    }
}

# Keep the assembly resolver registered for Windows PowerShell
# It's needed at runtime when SMO and other assemblies try to resolve dependencies
# The resolver handles version mismatches (e.g., SMO requesting SqlClient 5.0.0.0 when 6.0.2 is loaded)
if ($PSVersionTable.PSEdition -ne "Core" -and $redirector) {
    # Store the redirector in script scope so it stays alive and can be accessed if needed
    $script:assemblyRedirector = $redirector
}
