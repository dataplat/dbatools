#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Microsoft.Management.Infrastructure.Options;

namespace Dataplat.Dbatools.Commands;

/// <summary>Reads the process-local connection record exported by the pinned Set-DbaCmConnection example.</summary>
internal static class ManagementConnectionSnapshot
{
    internal static PSObject? Find(object? input)
    {
        if (input is null)
            return null;
        PSObject source = PSObject.AsPSObject(input);
        if (source.BaseObject is not PSCustomObject || source.TypeNames.Count == 0)
            return null;
        string expected = "Deserialized." + typeof(ManagementConnection).FullName;
        return string.Equals(source.TypeNames[0], expected, StringComparison.OrdinalIgnoreCase) ? source : null;
    }

    internal static string? Name(PSObject? source)
    {
        if (source is null)
            return null;
        PSPropertyInfo? property = source.Properties[nameof(ManagementConnection.ComputerName)];
        if (property is not PSNoteProperty && property is not PSProperty)
            return null;
        string? name = Unwrap(property.Value) as string;
        return name is not null && Utility.Validation.IsValidComputerTarget(name) ? name : null;
    }

    internal static ManagementConnection? Restore(PSObject source, string name)
    {
        ManagementConnection restored = new() { ComputerName = name };
        try
        {
            SetScalar<ManagementConnectionProtocolState>(source, nameof(restored.CimRM), v => restored.CimRM = v);
            SetScalar<ManagementConnectionProtocolState>(source, nameof(restored.CimDCOM), v => restored.CimDCOM = v);
            SetScalar<ManagementConnectionProtocolState>(source, nameof(restored.Wmi), v => restored.Wmi = v);
            SetScalar<ManagementConnectionProtocolState>(source, nameof(restored.PowerShellRemoting), v => restored.PowerShellRemoting = v);
            SetScalar<DateTime>(source, nameof(restored.LastCimRM), v => restored.LastCimRM = v);
            SetScalar<DateTime>(source, nameof(restored.LastCimDCOM), v => restored.LastCimDCOM = v);
            SetScalar<DateTime>(source, nameof(restored.LastWmi), v => restored.LastWmi = v);
            SetScalar<DateTime>(source, nameof(restored.LastPowerShellRemoting), v => restored.LastPowerShellRemoting = v);
            // A data-only import must not silently install credentials or change the host's authentication policy.
            if (Data(source, nameof(restored.Credentials)) is not null || HasSavedCredentials(source))
                return null;
            MatchScalar(source, nameof(restored.OverrideExplicitCredential), () => restored.OverrideExplicitCredential);
            MatchScalar(source, nameof(restored.OverrideConnectionPolicy), () => restored.OverrideConnectionPolicy);
            MatchScalar(source, nameof(restored.UseWindowsCredentials), () => restored.UseWindowsCredentials);
            MatchScalar(source, nameof(restored.EnableCredentialFailover), () => restored.EnableCredentialFailover);
            SetScalar<bool>(source, nameof(restored.WindowsCredentialsAreBad), v => restored.WindowsCredentialsAreBad = v);
            MatchScalar(source, nameof(restored.DisableBadCredentialCache), () => restored.DisableBadCredentialCache);
            SetScalar<bool>(source, nameof(restored.DisableCimPersistence), v => restored.DisableCimPersistence = v);
            MatchScalar(source, nameof(restored.DisableCredentialAutoRegister), () => restored.DisableCredentialAutoRegister);
            restored.CimWinRMOptions = ReadOptions<WSManSessionOptions>(source, nameof(restored.CimWinRMOptions), CimOptionDefaults.WinRM, RestoreWinRM);
            restored.CimDComOptions = ReadOptions<DComSessionOptions>(source, nameof(restored.CimDComOptions), CimOptionDefaults.DCom, RestoreDCom);
            if (ConnectionHost.Connections.TryGetValue(name, out ManagementConnection? existing) && existing is not null)
                return UpdateCachedHistory(existing, restored);
            return restored;
        }
        catch (Exception failure) when (failure is InvalidCastException || failure is PSInvalidCastException || failure is ArgumentException)
        {
            return null;
        }
    }

    private static ManagementConnection UpdateCachedHistory(ManagementConnection existing, ManagementConnection imported)
    {
        // A file can update history without replacing a live record's credentials, protocol restrictions or transport options.
        if (existing.CimRM != ManagementConnectionProtocolState.Disabled)
            existing.CimRM = imported.CimRM;
        if (existing.CimDCOM != ManagementConnectionProtocolState.Disabled)
            existing.CimDCOM = imported.CimDCOM;
        if (existing.Wmi != ManagementConnectionProtocolState.Disabled)
            existing.Wmi = imported.Wmi;
        if (existing.PowerShellRemoting != ManagementConnectionProtocolState.Disabled)
            existing.PowerShellRemoting = imported.PowerShellRemoting;
        existing.LastCimRM = imported.LastCimRM;
        existing.LastCimDCOM = imported.LastCimDCOM;
        existing.LastWmi = imported.LastWmi;
        existing.LastPowerShellRemoting = imported.LastPowerShellRemoting;
        existing.DisableCimPersistence = imported.DisableCimPersistence;
        if (existing.CimWinRMOptions is null)
            existing.CimWinRMOptions = imported.CimWinRMOptions;
        if (existing.CimDComOptions is null)
            existing.CimDComOptions = imported.CimDComOptions;
        return existing;
    }

    private static bool HasSavedCredentials(PSObject source)
    {
        object? entries = Unwrap(Data(source, nameof(ManagementConnection.KnownBadCredentials)));
        if (entries is null)
            return false;
        if (entries is ArrayList list)
            return list.Count != 0;
        if (entries is Array array)
            return array.Length != 0;
        if (entries is List<PSCredential> credentials)
            return credentials.Count != 0;
        return true;
    }

    private static T? ReadOptions<T>(PSObject record, string name, Func<T> create, Action<PSObject, T> restore) where T : CimSessionOptions
    {
        object? value = Data(record, name);
        if (value is null)
            return null;

        PSObject snapshot = PSObject.AsPSObject(value);
        if (snapshot.BaseObject is not PSCustomObject || snapshot.TypeNames.Count == 0 ||
            !string.Equals(snapshot.TypeNames[0], "Deserialized." + typeof(T).FullName, StringComparison.OrdinalIgnoreCase))
            throw new InvalidCastException();
        T options = create();
        SetScalar<TimeSpan>(snapshot, nameof(options.Timeout), v => options.Timeout = v);
        SetCulture(snapshot, nameof(options.Culture), v => options.Culture = v);
        SetCulture(snapshot, nameof(options.UICulture), v => options.UICulture = v);
        restore(snapshot, options);
        return options;
    }

    private static void SetCulture(PSObject source, string name, Action<CultureInfo> set)
    {
        object? value = Data(source, name);
        if (value is null)
            return;
        object? raw = Unwrap(value);
        if (raw is CultureInfo culture)
            set(culture);
        else if (raw is string text)
            set(CultureInfo.GetCultureInfo(text));
        else if (value is PSObject wrapped && wrapped.BaseObject is PSCustomObject &&
                 Unwrap(Data(wrapped, nameof(CultureInfo.Name))) is string cultureName)
            set(CultureInfo.GetCultureInfo(cultureName));
        else
            throw new InvalidCastException();
    }

    private static void RestoreDCom(PSObject source, DComSessionOptions options)
    {
        MatchScalar(source, nameof(options.PacketPrivacy), () => options.PacketPrivacy);
        MatchScalar(source, nameof(options.PacketIntegrity), () => options.PacketIntegrity);
        MatchScalar(source, nameof(options.Impersonation), () => options.Impersonation);
    }

    private static void RestoreWinRM(PSObject source, WSManSessionOptions options)
    {
        MatchScalar(source, nameof(options.DestinationPort), () => options.DestinationPort);
        SetScalar<uint>(source, nameof(options.MaxEnvelopeSize), v => options.MaxEnvelopeSize = v);
        MatchScalar(source, nameof(options.CertCACheck), () => options.CertCACheck);
        MatchScalar(source, nameof(options.CertCNCheck), () => options.CertCNCheck);
        MatchScalar(source, nameof(options.CertRevocationCheck), () => options.CertRevocationCheck);
        MatchScalar(source, nameof(options.UseSsl), () => options.UseSsl);
        MatchScalar(source, nameof(options.ProxyType), () => options.ProxyType);
        SetScalar<PacketEncoding>(source, nameof(options.PacketEncoding), v => options.PacketEncoding = v);
        MatchScalar(source, nameof(options.NoEncryption), () => options.NoEncryption);
        MatchScalar(source, nameof(options.EncodePortInServicePrincipalName), () => options.EncodePortInServicePrincipalName);
        if (Data(source, nameof(options.HttpUrlPrefix)) is not null)
            throw new InvalidCastException();
    }

    private static void MatchScalar<T>(PSObject source, string name, Func<T> current)
    {
        SetScalar<T>(source, name, value =>
        {
            if (!EqualityComparer<T>.Default.Equals(value, current()))
                throw new InvalidCastException();
        });
    }

    private static void SetScalar<T>(PSObject source, string name, Action<T> set)
    {
        object? data = Unwrap(Data(source, name));
        if (data is null)
            return;
        if (data is T value)
        {
            set(value);
            return;
        }
        if (data is not string && data is not int && data is not uint && data is not long)
            throw new InvalidCastException();
        set(LanguagePrimitives.ConvertTo<T>(data));
    }

    private static object? Data(PSObject source, string name)
    {
        PSPropertyInfo? property = source.Properties[name];
        if (property is null)
            return null;
        if (property is not PSNoteProperty && property is not PSProperty)
            throw new InvalidCastException();
        return property.Value;
    }

    private static object? Unwrap(object? value) => value is PSObject wrapped ? wrapped.BaseObject : value;
}
