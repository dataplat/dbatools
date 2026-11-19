#nullable enable
#pragma warning disable CA1416 // Windows-only: performance counters through pdh.dll and logon through advapi32, as Get-Counter reads them

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Net;
using System.Reflection;
using System.Resources;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace Dataplat.Dbatools.Commands;

// The pin's Get-Counter call, done here on pdh.dll as Microsoft.PowerShell.Commands.GetCounterCommand and its PdhHelper do it (PowerShell,
// MIT): the counter paths joined with the computer names, PdhExpandWildCardPath, PdhValidatePath, one query with PdhAddCounter per path, a
// first PdhCollectQueryDataWithTime that is not written, then one sample set per collection, SampleInterval seconds apart, each sample from
// PdhGetRawCounterValue, PdhGetFormattedCounterValue (PDH_FMT_DOUBLE | PDH_FMT_NOCAP100), PdhGetCounterInfo and PdhGetCounterTimeBase
// (Microsoft Learn, "Using the PDH Functions to Consume Counter Data"). The sets and samples are Get-Counter's own
// PerformanceCounterSampleSet and PerformanceCounterSample objects, made through reflection from the Microsoft.PowerShell.Commands.Diagnostics
// assembly; the Get-Counter cmdlet itself never runs.
// -Credential (upstream defect, corrected): Get-Counter has no -Credential parameter on either edition (Microsoft Learn, Get-Counter), so
// upstream failed every call that had a credential. Here the reads run impersonating a LOGON32_LOGON_NEW_CREDENTIALS logon of the credential
// (Microsoft Learn, LogonUserW), which keeps the local identity and uses the credential for the connections to other computers.
public sealed partial class GetDbaPfDataCollectorCounterSampleCommand
{
    // The pin's Get-Counter parameters for one counter row ($params).
    private sealed class CounterQuery
    {
        // -Counter: $counterobject.Name
        public object? Counter { get; set; }
        // -ComputerName: $counterobject.ComputerName for a computer that is not this one, else not passed
        public object? ComputerName { get; set; }
        public PSCredential? Credential { get; set; }
        public bool Continuous { get; set; }
        public bool ListSet { get; set; }
        // 0 is not passed: Get-Counter's default of 1
        public int MaxSamples { get; set; }
        // 0 is not passed: Get-Counter's default of 1
        public int SampleInterval { get; set; }
    }

    // An error that ends the Get-Counter call: a refusal of its parameters, a terminating error, or under -ErrorAction Stop a written error.
    private sealed class CounterFailure : Exception, IContainsErrorRecord
    {
        internal CounterFailure(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            ErrorRecord = record;
        }

        public ErrorRecord ErrorRecord { get; }
    }

    // One counter of the query: the lowercase path Get-Counter reports, its handle and its lowercase instance name.
    private sealed class QueryCounter
    {
        public string Path { get; set; } = String.Empty;
        public IntPtr Handle { get; set; }
        public string? InstanceName { get; set; }
    }

    private const uint PdhValidData = 0x0;
    private const uint PdhMoreData = 0x800007D2;
    private const uint PdhNoData = 0x800007D5;
    private const uint PdhInvalidData = 0xC0000BC6;
    private const uint PdhFormatDouble = 0x00000200;
    private const uint PdhFormatNoCap100 = 0x00008000;
    private const uint PdhRefreshCounters = 4;
    // System.Diagnostics.PerformanceCounterType.RawBase, the type Get-Counter gives a sample whose raw value cannot be read
    private const uint RawBaseCounterType = 0x40030403;
    private const int Logon32LogonNewCredentials = 9;
    private const int Logon32ProviderWinnt50 = 3;
    private const string SampleTypeName = "Microsoft.PowerShell.Commands.GetCounter.PerformanceCounterSample";
    private const string SampleSetTypeName = "Microsoft.PowerShell.Commands.GetCounter.PerformanceCounterSampleSet";

    // The assembly that holds Get-Counter's types: Windows PowerShell 3 to 5.1 keep version 3.0.0.0 in the global assembly cache, and
    // PowerShell 7 resolves it by name from its own folder.
    private static readonly string[] DiagnosticsAssemblyNames =
    {
        "Microsoft.PowerShell.Commands.Diagnostics, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35",
        "Microsoft.PowerShell.Commands.Diagnostics",
    };

    // Get-Counter's types, found once: null when they cannot be loaded.
    private static readonly Lazy<Type[]?> CounterSampleTypes = new(LoadCounterSampleTypes);

    // Get-Counter @params for one counter row. written gets each error Get-Counter writes and goes on after; output gets each sample set.
    private void ReadCounter(CounterQuery query, Action<ErrorRecord> written, Action<object> output)
    {
        if (CancellationToken.IsCancellationRequested)
            throw new PipelineStoppedException();

        string[] counters = BindCounterParameters(query, out string[]? computers);

        // GetCounterCommand.BeginProcessing
        if (query.Continuous && query.MaxSamples != 0)
            throw new CounterFailure(new ErrorRecord(new Exception(CounterText("CounterContinuousOrMaxSamples", "The Continuous parameter and the MaxSamples parameter cannot be used in the same command.")),
                "CounterContinuousOrMaxSamples", ErrorCategory.InvalidArgument, null));

        using SafeAccessTokenHandle? token = query.Credential is null ? null : Logon(query.Credential);

        // GetCounterCommand.ProcessGetCounter: each path expanded and validated; a path that does not expand is a written error.
        List<string> expanded = new();
        foreach (string path in CombineComputersAndPaths(counters, computers))
        {
            string localized = LocalizedPath(path);
            List<string> paths = new();
            uint result = AsUser(token, () => ExpandWildCardPath(localized, paths));
            if (result != PdhValidData)
            {
                written(PdhError(result));
                continue;
            }

            foreach (string candidate in paths)
            {
                if (AsUser(token, () => PdhValidatePath(candidate)) != PdhValidData)
                {
                    written(new ErrorRecord(new Exception(String.Format(CultureInfo.InvariantCulture, CounterText("CounterPathIsInvalid", PathIsInvalidText), localized)),
                        "CounterPathIsInvalid", ErrorCategory.InvalidResult, null));
                    continue;
                }
                expanded.Add(candidate);
            }
        }

        if (expanded.Count == 0)
            return;

        IntPtr pdhQuery = IntPtr.Zero;
        try
        {
            uint opened = AsUser(token, () => PdhOpenQuery(null, IntPtr.Zero, out pdhQuery));
            if (opened != PdhValidData)
                written(PdhError(opened));

            List<QueryCounter> added = new();
            uint addResult = AsUser(token, () => AddCounters(pdhQuery, expanded, added));
            if (addResult != PdhValidData)
                throw new CounterFailure(PdhError(addResult));

            long maxSamples = query.Continuous ? -1 : (query.MaxSamples != 0 ? query.MaxSamples : 1);
            int interval = (int)Math.Min((query.SampleInterval != 0 ? (long)query.SampleInterval : 1) * 1000, Int32.MaxValue);
            bool skip = true;
            long reads = 0;
            while (true)
            {
                object? set = null;
                bool skipRead = skip;
                uint read = AsUser(token, () => ReadNextSet(pdhQuery, added, skipRead, out set));
                if (read == PdhValidData)
                {
                    if (!skip)
                    {
                        WriteSampleSet(set!, written, output);
                        reads++;
                    }
                    skip = false;
                }
                else if (read == PdhNoData || read == PdhInvalidData)
                {
                    written(PdhError(read));
                    skip = true;
                    reads++;
                }
                else
                {
                    throw new CounterFailure(PdhError(read));
                }

                if (maxSamples != -1 && reads >= maxSamples)
                    break;
                // Ctrl+C ends the wait, as it ends Get-Counter's.
                if (CancellationToken.WaitHandle.WaitOne(interval))
                    break;
            }
        }
        finally
        {
            if (pdhQuery != IntPtr.Zero)
                PdhCloseQuery(pdhQuery);
        }
    }

    // The parameter binding of Get-Counter @params, with the binder's refusals: -Counter $null, a -MaxSamples or -SampleInterval below 1
    // ([ValidateRange(1, ...)]) and -ListSet with -Counter, which are parameters of different Get-Counter parameter sets.
    // -ListSet (upstream defect, reported to the operator, not corrected): the pin's [switch[]] cannot carry the documented wildcard
    // patterns and always fails this way; making it work changes the parameter type.
    private static string[] BindCounterParameters(CounterQuery query, out string[]? computers)
    {
        computers = query.ComputerName is null ? null : BindStrings("ComputerName", query.ComputerName);
        if (query.Counter is null)
            throw new CounterFailure(new ErrorRecord(new ParameterBindingException("Cannot bind argument to parameter 'Counter' because it is null."),
                "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null));
        string[] counters = BindStrings("Counter", query.Counter);
        if (query.MaxSamples < 0)
            throw new CounterFailure(RangeError("MaxSamples", query.MaxSamples));
        if (query.SampleInterval < 0)
            throw new CounterFailure(RangeError("SampleInterval", query.SampleInterval));
        if (query.ListSet)
            throw new CounterFailure(new ErrorRecord(new ParameterBindingException(AmbiguousParameterSetMessage()), "AmbiguousParameterSet", ErrorCategory.InvalidArgument, null));
        return counters;
    }

    // The binder's AmbiguousParameterSet text: PowerShell 7 adds a second sentence to Windows PowerShell's.
    private static string AmbiguousParameterSetMessage()
    {
        const string message = "Parameter set cannot be resolved using the specified named parameters.";
        if (RuntimeInformation.FrameworkDescription.StartsWith(".NET Framework", StringComparison.Ordinal))
            return message;
        return message + " One or more parameters issued cannot be used together or an insufficient number of parameters were provided.";
    }

    // A [string[]] parameter of Get-Counter: a value it cannot take is the binder's refusal.
    private static string[] BindStrings(string parameter, object value)
    {
        try
        {
            return (string[])LanguagePrimitives.ConvertTo(value, typeof(string[]), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException ex)
        {
            string message = String.Format(CultureInfo.CurrentCulture, "Cannot convert '{0}' to the type 'System.String[]' required by parameter '{1}'. {2}", value, parameter, ex.Message);
            throw new CounterFailure(new ErrorRecord(new ParameterBindingException(message, ex), "CannotConvertArgumentNoMessage", ErrorCategory.InvalidArgument, null));
        }
    }

    private static ErrorRecord RangeError(string parameter, int value)
    {
        string message = String.Format(CultureInfo.CurrentCulture,
            "Cannot validate argument on parameter '{0}'. The {1} argument is less than the minimum allowed range of 1. Supply an argument that is greater than or equal to 1 and then try the command again.",
            parameter, value);
        return new ErrorRecord(new ParameterBindingException(message), "ParameterArgumentValidationError", ErrorCategory.InvalidData, null);
    }

    // GetCounterCommand.CombineMachinesAndCounterPaths
    private static List<string> CombineComputersAndPaths(string[] counters, string[]? computers)
    {
        List<string> paths = new();
        if (computers is null || computers.Length == 0)
        {
            paths.AddRange(counters);
            return paths;
        }

        foreach (string path in counters)
        {
            if (path.StartsWith("\\\\", StringComparison.OrdinalIgnoreCase))
            {
                paths.Add(path);
                continue;
            }
            foreach (string computer in computers)
            {
                string slash = path.Length > 0 && path[0] == '\\' ? String.Empty : "\\";
                paths.Add(computer.StartsWith("\\\\", StringComparison.OrdinalIgnoreCase) ? computer + slash + path : "\\\\" + computer + slash + path);
            }
        }
        return paths;
    }

    // GetCounterCommand: under the fr-FR user interface culture the apostrophes of a counter path become the typographic one.
    private static string LocalizedPath(string path)
    {
        if (!String.Equals(CultureInfo.CurrentUICulture.Name, "fr-FR", StringComparison.Ordinal))
            return path;
        return path.Replace('\u0027', '\u2019').Replace('\u02BC', '\u2019').Replace('\u275C', '\u2019');
    }

    // PdhHelper.ExpandWildCardPath: the paths that match, read from the double-null-terminated list.
    private static uint ExpandWildCardPath(string path, List<string> expanded)
    {
        uint length = 0;
        uint result = PdhExpandWildCardPath(null, path, IntPtr.Zero, ref length, PdhRefreshCounters);
        if (result != PdhMoreData)
            return result;

        IntPtr buffer = Marshal.AllocHGlobal((int)length * sizeof(char));
        try
        {
            result = PdhExpandWildCardPath(null, path, buffer, ref length, PdhRefreshCounters);
            if (result == PdhValidData)
                expanded.AddRange((Marshal.PtrToStringUni(buffer, (int)length) ?? String.Empty).TrimEnd('\0').Split('\0'));
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
        return result;
    }

    // PdhHelper.AddCounters: each path once, by its lowercase form; an error only when no path could be added.
    private static uint AddCounters(IntPtr query, List<string> paths, List<QueryCounter> added)
    {
        uint result = PdhValidData;
        bool any = false;
        HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (string path in paths)
        {
            result = PdhAddCounter(query, path, IntPtr.Zero, out IntPtr handle);
            if (result != PdhValidData)
                continue;
            any = true;
            string key = path.ToLowerInvariant();
            if (seen.Add(key))
                added.Add(new QueryCounter { Path = key, Handle = handle, InstanceName = InstanceName(path)?.ToLowerInvariant() });
        }
        return any ? PdhValidData : result;
    }

    // PdhHelper.ParsePath: the instance name of a counter path, null when it has none or cannot be parsed.
    private static string? InstanceName(string path)
    {
        uint size = 0;
        if (PdhParseCounterPath(path, IntPtr.Zero, ref size, 0) != PdhMoreData)
            return null;
        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            if (PdhParseCounterPath(path, buffer, ref size, 0) != PdhValidData)
                return null;
            // PDH_COUNTER_PATH_ELEMENTS: szMachineName, szObjectName, szInstanceName, ...
            IntPtr instance = Marshal.ReadIntPtr(buffer, 2 * IntPtr.Size);
            return instance == IntPtr.Zero ? null : Marshal.PtrToStringUni(instance);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    // PdhHelper.ReadNextSet: one collection; when it is not skipped, a sample set of every counter, and an error only when every sample
    // is invalid.
    private static uint ReadNextSet(IntPtr query, List<QueryCounter> counters, bool skip, out object? set)
    {
        set = null;
        uint result = PdhCollectQueryDataWithTime(query, out long batchTime);
        if (skip)
            return result;
        if (result != PdhValidData && result != PdhNoData)
            return result;

        DateTime batchStamp = result != PdhNoData ? new DateTime(DateTime.FromFileTimeUtc(batchTime).Ticks, DateTimeKind.Local) : DateTime.Now;
        object?[] samples = new object?[counters.Count];
        int invalid = 0;
        uint lastError = PdhValidData;
        for (int index = 0; index < counters.Count; index++)
        {
            QueryCounter counter = counters[index];
            CounterInfo(counter.Handle, out uint counterType, out uint defaultScale, out ulong timeBase);

            result = PdhGetRawCounterValue(counter.Handle, out _, out PdhRawCounter raw);
            if (result != PdhValidData)
            {
                samples[index] = NewSample(counter.Path, counter.InstanceName, 0, 0, 0, 0, RawBaseCounterType, defaultScale, timeBase, batchStamp,
                    (ulong)batchStamp.ToFileTime(), raw.CStatus == PdhValidData ? result : raw.CStatus);
                invalid++;
                lastError = result;
                continue;
            }

            long stampTime = ((long)raw.TimeStampHigh << 32) + raw.TimeStampLow;
            DateTime stamp = new(DateTime.FromFileTimeUtc(stampTime).Ticks, DateTimeKind.Local);
            result = PdhGetFormattedCounterValue(counter.Handle, PdhFormatDouble | PdhFormatNoCap100, out uint formattedType, out PdhFormattedValue formatted);
            if (result != PdhValidData)
            {
                samples[index] = NewSample(counter.Path, counter.InstanceName, 0, (ulong)raw.FirstValue, (ulong)raw.SecondValue, raw.MultiCount, counterType,
                    defaultScale, timeBase, stamp, (ulong)stampTime, formatted.CStatus == PdhValidData ? result : raw.CStatus);
                invalid++;
                lastError = result;
                continue;
            }

            samples[index] = NewSample(counter.Path, counter.InstanceName, formatted.DoubleValue, (ulong)raw.FirstValue, (ulong)raw.SecondValue,
                raw.MultiCount, formattedType, defaultScale, timeBase, stamp, (ulong)stampTime, formatted.CStatus);
        }

        set = NewSampleSet(batchStamp, samples);
        return invalid == samples.Length ? lastError : PdhValidData;
    }

    // PdhHelper.GetCounterInfoPlus: the counter type and default scale of PDH_COUNTER_INFO, and the time base. Values stay 0 when unread.
    private static void CounterInfo(IntPtr counter, out uint counterType, out uint defaultScale, out ulong timeBase)
    {
        counterType = 0;
        defaultScale = 0;
        timeBase = 0;
        uint size = 0;
        if (PdhGetCounterInfo(counter, 0, ref size, IntPtr.Zero) != PdhMoreData)
            return;
        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            if (PdhGetCounterInfo(counter, 0, ref size, buffer) == PdhValidData)
            {
                // PDH_COUNTER_INFO: dwLength, dwType, CVersion, CStatus, lScale, lDefaultScale, ...
                counterType = (uint)Marshal.ReadInt32(buffer, 4);
                defaultScale = (uint)Marshal.ReadInt32(buffer, 20);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
        if (PdhGetCounterTimeBase(counter, out long counterTimeBase) == PdhValidData)
            timeBase = (ulong)counterTimeBase;
    }

    // GetCounterCommand.WriteSampleSetObject: a written error when any sample's Status is not 0, then the set.
    private static void WriteSampleSet(object set, Action<ErrorRecord> written, Action<object> output)
    {
        foreach (object? sample in GetDbaPfDataCollectorCommand.ForeachItems(PSObject.AsPSObject(set).Properties["CounterSamples"]?.Value))
        {
            object? status = sample is null ? null : PSObject.AsPSObject(sample).Properties["Status"]?.Value;
            if (Convert.ToUInt32(status, CultureInfo.InvariantCulture) != 0)
            {
                written(new ErrorRecord(new Exception(CounterText("CounterSampleDataInvalid", "The data in one of the performance counter samples is not valid. View the Status property for each PerformanceCounterSample object to make sure it contains valid data.")),
                    "CounterApiError", ErrorCategory.InvalidResult, null));
                break;
            }
        }
        output(set);
    }

    // GetCounterCommand.ReportPdhError: pdh.dll's own message for the status, else Get-Counter's CounterApiError text.
    private static ErrorRecord PdhError(uint status)
    {
        string message = PdhMessage(status) ?? String.Format(CultureInfo.InvariantCulture, CounterText("CounterApiError", "Internal performance counter API call failed. Error: {0:x8}."), status);
        return new ErrorRecord(new Exception(message), "CounterApiError", ErrorCategory.InvalidResult, null);
    }

    // CommonUtilities.FormatMessageFromModule: the message table of pdh.dll, then the system's; the trailing line break removed.
    private static string? PdhMessage(uint status)
    {
        IntPtr module = LoadLibraryEx("pdh.dll", IntPtr.Zero, LoadLibraryAsDatafile);
        if (module == IntPtr.Zero)
            return null;
        try
        {
            char[] text = new char[1024];
            uint length = FormatMessage(FormatMessageIgnoreInserts | FormatMessageFromSystem | FormatMessageFromHmodule, module, status, 0, text, (uint)text.Length, IntPtr.Zero);
            if (length == 0)
                return null;
            string message = new(text, 0, (int)Math.Min(length, (uint)text.Length));
            return message.EndsWith(Environment.NewLine, StringComparison.Ordinal) ? message.Substring(0, message.Length - Environment.NewLine.Length) : message;
        }
        finally
        {
            FreeLibrary(module);
        }
    }

    // The body under the credential's logon when there is one (WindowsIdentity.RunImpersonated), else as the caller.
    private static T AsUser<T>(SafeAccessTokenHandle? token, Func<T> body)
    {
        return token is null ? body() : WindowsIdentity.RunImpersonated(token, body);
    }

    // A LOGON32_LOGON_NEW_CREDENTIALS logon of the credential: the caller's local identity, the credential for outbound connections.
    private static SafeAccessTokenHandle Logon(PSCredential credential)
    {
        NetworkCredential network = credential.GetNetworkCredential() ?? new NetworkCredential(credential.UserName, String.Empty);
        string? domain = String.IsNullOrEmpty(network.Domain) ? null : network.Domain;
        IntPtr password = credential.Password is null ? IntPtr.Zero : Marshal.SecureStringToGlobalAllocUnicode(credential.Password);
        try
        {
            if (!LogonUser(network.UserName, domain, password, Logon32LogonNewCredentials, Logon32ProviderWinnt50, out SafeAccessTokenHandle token))
            {
                Win32Exception failure = new(Marshal.GetLastWin32Error());
                throw new CounterFailure(new ErrorRecord(failure, "CounterCredentialLogonFailed", ErrorCategory.SecurityError, credential.UserName));
            }
            return token;
        }
        finally
        {
            if (password != IntPtr.Zero)
                Marshal.ZeroFreeGlobalAllocUnicode(password);
        }
    }

    // A PerformanceCounterSample with Get-Counter's values; without the type, an object with its properties and type name.
    private static object NewSample(string path, string? instanceName, double cookedValue, ulong rawValue, ulong secondValue, uint multipleCount,
        uint counterType, uint defaultScale, ulong timeBase, DateTime timestamp, ulong timestamp100NSec, uint status)
    {
        Type[]? types = CounterSampleTypes.Value;
        if (types is null)
        {
            PSObject fallback = new();
            fallback.TypeNames.Insert(0, SampleTypeName);
            fallback.Properties.Add(new PSNoteProperty("Path", path));
            fallback.Properties.Add(new PSNoteProperty("InstanceName", instanceName)); // style-ok: cs-output-props a performance counter instance of a sample, not a SQL Server instance.
            fallback.Properties.Add(new PSNoteProperty("CookedValue", cookedValue));
            fallback.Properties.Add(new PSNoteProperty("RawValue", rawValue));
            fallback.Properties.Add(new PSNoteProperty("SecondValue", secondValue));
            fallback.Properties.Add(new PSNoteProperty("MultipleCount", multipleCount));
            fallback.Properties.Add(new PSNoteProperty("CounterType", counterType));
            fallback.Properties.Add(new PSNoteProperty("Timestamp", timestamp));
            fallback.Properties.Add(new PSNoteProperty("Timestamp100NSec", timestamp100NSec));
            fallback.Properties.Add(new PSNoteProperty("Status", status));
            fallback.Properties.Add(new PSNoteProperty("DefaultScale", defaultScale));
            fallback.Properties.Add(new PSNoteProperty("TimeBase", timeBase));
            return fallback;
        }

        object sample = Activator.CreateInstance(types[0], nonPublic: true)!;
        SetValue(sample, "Path", path);
        SetValue(sample, "InstanceName", instanceName);
        SetValue(sample, "CookedValue", cookedValue);
        SetValue(sample, "RawValue", rawValue);
        SetValue(sample, "SecondValue", secondValue);
        SetValue(sample, "MultipleCount", multipleCount);
        PropertyInfo typeProperty = types[0].GetProperty("CounterType")!;
        typeProperty.SetValue(sample, Enum.ToObject(typeProperty.PropertyType, counterType), null);
        SetValue(sample, "Timestamp", timestamp);
        SetValue(sample, "Timestamp100NSec", timestamp100NSec);
        SetValue(sample, "Status", status);
        SetValue(sample, "DefaultScale", defaultScale);
        SetValue(sample, "TimeBase", timeBase);
        return sample;
    }

    // A PerformanceCounterSampleSet of the samples; without the type, an object with its properties and type name.
    private static object NewSampleSet(DateTime timestamp, object?[] samples)
    {
        Type[]? types = CounterSampleTypes.Value;
        if (types is null)
        {
            PSObject fallback = new();
            fallback.TypeNames.Insert(0, SampleSetTypeName);
            fallback.Properties.Add(new PSNoteProperty("Timestamp", timestamp));
            fallback.Properties.Add(new PSNoteProperty("CounterSamples", samples));
            return fallback;
        }

        Array typed = Array.CreateInstance(types[0], samples.Length);
        Array.Copy(samples, typed, samples.Length);
        object set = Activator.CreateInstance(types[1], nonPublic: true)!;
        SetValue(set, "Timestamp", timestamp);
        SetValue(set, "CounterSamples", typed);
        return set;
    }

    private static void SetValue(object target, string property, object? value)
    {
        target.GetType().GetProperty(property)!.SetValue(target, value, null);
    }

    // PerformanceCounterSample and PerformanceCounterSampleSet, or null when the assembly that holds them cannot be loaded.
    // Get-Counter's own message table (GetEventResources in Microsoft.PowerShell.Commands.Diagnostics), read from the engine's assembly
    // in the current UI culture as Get-Counter reads it: Windows PowerShell 5.1 and PowerShell 7 differ (5.1's CounterPathIsInvalid has
    // two spaces before "is", measured, evidence/pin-pfsample-records-20261112.txt). Null when the table cannot be found.
    private static readonly Lazy<ResourceManager?> CounterResources = new(LoadCounterResources);

    // The English CounterPathIsInvalid text of the running engine, for when its table cannot be read.
    private static readonly string PathIsInvalidText = RuntimeInformation.FrameworkDescription.StartsWith(".NET Framework", StringComparison.Ordinal)
        ? "The {0} performance counter path  is not valid."
        : "The {0} performance counter path is not valid.";

    private static ResourceManager? LoadCounterResources()
    {
        Type[]? types = CounterSampleTypes.Value;
        if (types is null)
            return null;
        Assembly diagnostics = types[0].Assembly;
        foreach (string name in diagnostics.GetManifestResourceNames())
        {
            if (name.EndsWith("GetEventResources.resources", StringComparison.Ordinal))
                return new ResourceManager(name.Substring(0, name.Length - ".resources".Length), diagnostics);
        }
        return null;
    }

    // One Get-Counter message by its resource name, or the fallback text when the table or the name cannot be read.
    private static string CounterText(string name, string fallback)
    {
        try
        {
            return CounterResources.Value?.GetString(name, CultureInfo.CurrentUICulture) ?? fallback;
        }
        catch (MissingManifestResourceException)
        {
            return fallback;
        }
    }

    private static Type[]? LoadCounterSampleTypes()
    {
        foreach (string assemblyName in DiagnosticsAssemblyNames)
        {
            Assembly diagnostics;
            try
            {
                diagnostics = Assembly.Load(assemblyName);
            }
            catch (Exception ex) when (ex is FileNotFoundException || ex is FileLoadException || ex is BadImageFormatException)
            {
                // Not this engine's form of the name: the next one is tried, and without any the samples are objects with the same properties.
                continue;
            }
            Type? sample = diagnostics.GetType(SampleTypeName);
            Type? set = diagnostics.GetType(SampleSetTypeName);
            if (sample is not null && set is not null)
                return new[] { sample, set };
        }
        return null;
    }

    // pdh.h, winbase.h and libloaderapi.h, as Microsoft Learn documents them.
    [StructLayout(LayoutKind.Sequential)]
    private struct PdhRawCounter
    {
        public uint CStatus;
        public uint TimeStampLow;
        public uint TimeStampHigh;
        public long FirstValue;
        public long SecondValue;
        public uint MultiCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PdhFormattedValue
    {
        public uint CStatus;
        public double DoubleValue;
    }

    private const uint LoadLibraryAsDatafile = 0x00000002;
    private const uint FormatMessageIgnoreInserts = 0x00000200;
    private const uint FormatMessageFromHmodule = 0x00000800;
    private const uint FormatMessageFromSystem = 0x00001000;

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhOpenQuery(string? dataSource, IntPtr userData, out IntPtr query);

    [DllImport("pdh.dll")]
    private static extern uint PdhCloseQuery(IntPtr query);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhExpandWildCardPath(string? dataSource, string wildCardPath, IntPtr expandedPathList, ref uint pathListLength, uint flags);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhValidatePath(string fullPath);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhAddCounter(IntPtr query, string fullCounterPath, IntPtr userData, out IntPtr counter);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhParseCounterPath(string fullPath, IntPtr counterPathElements, ref uint bufferSize, uint flags);

    [DllImport("pdh.dll")]
    private static extern uint PdhCollectQueryDataWithTime(IntPtr query, out long timeStamp);

    [DllImport("pdh.dll")]
    private static extern uint PdhGetRawCounterValue(IntPtr counter, out uint counterType, out PdhRawCounter value);

    [DllImport("pdh.dll")]
    private static extern uint PdhGetFormattedCounterValue(IntPtr counter, uint format, out uint counterType, out PdhFormattedValue value);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhGetCounterInfo(IntPtr counter, byte retrieveExplainText, ref uint bufferSize, IntPtr buffer);

    [DllImport("pdh.dll")]
    private static extern uint PdhGetCounterTimeBase(IntPtr counter, out long timeBase);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool LogonUser(string userName, string? domain, IntPtr password, int logonType, int logonProvider, out SafeAccessTokenHandle token);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryEx(string fileName, IntPtr file, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeLibrary(IntPtr module);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint FormatMessage(uint flags, IntPtr source, uint messageId, uint languageId, [Out] char[] buffer, uint size, IntPtr arguments);
}
