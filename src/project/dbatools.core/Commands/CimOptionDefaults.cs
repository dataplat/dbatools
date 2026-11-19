#nullable enable

using Microsoft.Management.Infrastructure.Options;

namespace Dataplat.Dbatools.Commands;

/// <summary>Concrete defaults set by New-CimSessionOption for its two protocols.</summary>
internal static class CimOptionDefaults
{
    internal static WSManSessionOptions WinRM() => new()
    {
        DestinationPort = 0,
        MaxEnvelopeSize = 0,
        CertCACheck = true,
        CertCNCheck = true,
        CertRevocationCheck = true,
        UseSsl = false,
        ProxyType = ProxyType.WinHttp,
        PacketEncoding = PacketEncoding.Utf8,
        NoEncryption = false,
        EncodePortInServicePrincipalName = false
    };

    internal static DComSessionOptions DCom() => new()
    {
        PacketPrivacy = true,
        PacketIntegrity = true,
        Impersonation = ImpersonationType.Impersonate
    };
}
