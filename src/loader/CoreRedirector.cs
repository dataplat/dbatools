using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;

namespace Dataplat.Dbatools.Loader
{
    // This source ships in the dbatools module's library folder because Import-DbatoolsLibrary.ps1
    // reads and compiles it at import time. The namespace keeps it apart from the global
    // CoreRedirector type that dbatools.library (dbatools 2.x) compiles into the same session.
    public class CoreRedirector
    {
        private static string _libPath;
        private static bool _registered = false;
        private static readonly object _syncRoot = new object();
        private static readonly string _platformRid = ComputePlatformRid();
        private static readonly string _architectureRid = ComputeArchitectureRid();

        public static string LibPath
        {
            get { return _libPath; }
        }

        public static void Register(string libPath)
        {
            lock (_syncRoot)
            {
                if (_registered) return;
                _libPath = libPath;
                AssemblyLoadContext.Default.Resolving += OnResolving;
                AssemblyLoadContext.Default.ResolvingUnmanagedDll += OnResolvingUnmanagedDll;
                _registered = true;
            }
        }

        private static Assembly OnResolving(AssemblyLoadContext context, AssemblyName assemblyName)
        {
            string name = assemblyName.Name;

            // First, check if any version of this assembly is already loaded
            // This handles version mismatches (e.g., dbatools.dll requesting ConnectionInfo 17.100.0.0 when 17.200.0.0 is loaded)
            foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                try
                {
                    if (assembly.GetName().Name == name)
                    {
                        return assembly;
                    }
                }
                catch
                {
                    // Some assemblies may throw when accessing GetName()
                }
            }

            foreach (string dllPath in GetManagedAssemblyPaths(name))
            {
                if (File.Exists(dllPath))
                {
                    try
                    {
                        return AssemblyLoadContext.Default.LoadFromAssemblyPath(dllPath);
                    }
                    catch (Exception ex)
                    {
                        Trace.TraceWarning("Failed to load managed assembly from '{0}': {1}", dllPath, ex.Message);
                        // Failed to load, try the next candidate
                    }
                }
            }

            return null;
        }

        // This resolver is global to the load context, but it only returns module-owned native assets from _libPath.
        private static IntPtr OnResolvingUnmanagedDll(Assembly assembly, string libraryName)
        {
            if (String.IsNullOrEmpty(_architectureRid))
            {
                return IntPtr.Zero;
            }

            foreach (string fileName in GetNativeLibraryNames(libraryName))
            {
                string nativePath = Path.Combine(_libPath, "runtimes", _architectureRid, "native", fileName);
                if (File.Exists(nativePath))
                {
                    try
                    {
                        return NativeLibrary.Load(nativePath);
                    }
                    catch (Exception ex)
                    {
                        Trace.TraceWarning("Failed to load native library from '{0}': {1}", nativePath, ex.Message);
                        // Failed to load, try the next candidate
                    }
                }
            }

            return IntPtr.Zero;
        }

        private static string[] GetManagedAssemblyPaths(string name)
        {
            string fileName = name + ".dll";

            var paths = new List<string>();

            if (!String.IsNullOrEmpty(_platformRid))
            {
                paths.Add(Path.Combine(_libPath, "runtimes", _platformRid, "lib", "net8.0", fileName));
            }

            if (!String.IsNullOrEmpty(_architectureRid))
            {
                paths.Add(Path.Combine(_libPath, "runtimes", _architectureRid, "lib", "net8.0", fileName));
            }

            paths.Add(Path.Combine(_libPath, fileName));

            return paths.ToArray();
        }

        private static string[] GetNativeLibraryNames(string libraryName)
        {
            var names = new List<string>();
            names.Add(libraryName);

            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                if (!libraryName.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
                {
                    names.Add(libraryName + ".dll");
                }
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                if (!libraryName.EndsWith(".dylib", StringComparison.OrdinalIgnoreCase))
                {
                    names.Add(libraryName + ".dylib");
                    names.Add("lib" + libraryName + ".dylib");
                }
            }
            else
            {
                if (!libraryName.EndsWith(".so", StringComparison.OrdinalIgnoreCase))
                {
                    names.Add(libraryName + ".so");
                    names.Add("lib" + libraryName + ".so");
                }
            }

            return names.ToArray();
        }

        private static string ComputePlatformRid()
        {
            // Managed runtime assets used by the module, especially SqlClient, ship
            // win/unix folders. OS-specific native assets are handled by ComputeArchitectureRid.
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                return "win";
            }

            return "unix";
        }

        private static string ComputeArchitectureRid()
        {
            string osPart;
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                osPart = "win";
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                osPart = "linux";
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                osPart = "osx";
            }
            else
            {
                return null;
            }

            string architecture;
            switch (RuntimeInformation.ProcessArchitecture)
            {
                case Architecture.X86:
                    architecture = "x86";
                    break;
                case Architecture.X64:
                    architecture = "x64";
                    break;
                case Architecture.Arm:
                    architecture = "arm";
                    break;
                case Architecture.Arm64:
                    architecture = "arm64";
                    break;
                default:
                    return null;
            }

            return osPart + "-" + architecture;
        }
    }
}
