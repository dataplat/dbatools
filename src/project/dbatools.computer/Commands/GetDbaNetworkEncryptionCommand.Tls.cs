#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

public sealed partial class GetDbaNetworkEncryptionCommand
{
    private void TlsMessage(MessageLevel level, string message)
        => WriteAttributedMessage("Get-SqlServerTlsCertificate", level, message);

    private X509Certificate2 ReadCertificate(string computer, string instance, int port)
    {
        const int timeout = 5000;
        string pipe = string.IsNullOrEmpty(instance) ? @"sql\query" : string.Format(@"MSSQL${0}\sql\query", instance);
        if (port <= 0)
        {
            using UdpClient browser = new(computer, 1434);
            browser.Client.SendTimeout = timeout;
            browser.Client.ReceiveTimeout = timeout;
            browser.Send(new byte[] { 3 }, 1);
            IPEndPoint endpoint = new(IPAddress.Any, 0);
            byte[] reply = browser.Receive(ref endpoint);
            if (reply.Length < 3 || (reply[1] | reply[2] << 8) > reply.Length - 3) throw new IOException("Invalid SQL Browser response.");
            string raw = Encoding.UTF8.GetString(reply, 3, reply[1] | reply[2] << 8);
            TlsMessage(MessageLevel.Verbose, string.Format("Recieved SQL Browser response: '{0}'", raw));
            Dictionary<string, string>? selected = null;
            foreach (string block in raw.Split(new[] { ";;" }, StringSplitOptions.RemoveEmptyEntries))
            {
                string[] fields = block.Split(';');
                Dictionary<string, string> values = new(StringComparer.OrdinalIgnoreCase);
                for (int i = 0; i + 1 < fields.Length; i += 2) values[fields[i]] = fields[i + 1];
                if (string.IsNullOrEmpty(instance) || (values.TryGetValue("InstanceName", out string? name) && string.Equals(name, instance, StringComparison.OrdinalIgnoreCase)))
                { selected = values; break; }
            }
            if (selected is not null && selected.TryGetValue("tcp", out string? tcp) && !string.IsNullOrEmpty(tcp))
            {
                port = int.Parse(tcp, System.Globalization.CultureInfo.InvariantCulture);
                computer = selected["ServerName"];
            }
            else if (selected is not null && selected.TryGetValue("np", out string? namedPipe) && !string.IsNullOrEmpty(namedPipe))
            {
                computer = selected["ServerName"];
                pipe = System.Text.RegularExpressions.Regex.Replace(namedPipe, @"\\\\.*?\\pipe\\(.*)", "$1");
            }
            else throw new InvalidOperationException("Failed to receive any SQL Browser responses from " + computer + ":1434, cannot continue");
        }
        using TcpClient socket = new();
        Stream transport;
        if (port > 0)
        {
            TlsMessage(MessageLevel.Verbose, "Connecting to TCP/IP endpoint " + computer + ":" + port);
            if (!socket.ConnectAsync(computer, port).Wait(timeout)) throw new TimeoutException("Timed out connecting to TCP/IP endpoint " + computer + ":" + port);
            transport = socket.GetStream();
        }
        else
        {
            TlsMessage(MessageLevel.Verbose, @"Connecting to Named Pipe endpoint \\" + computer + @"\pipe\" + pipe);
            NamedPipeClientStream named = new(computer, pipe, PipeDirection.InOut);
            try { named.Connect(timeout); transport = named; }
            catch { named.Dispose(); throw; }
        }
        using (transport)
        using (CancellationToken.Register(() => transport.Dispose()))
        {
            TlsMessage(MessageLevel.Verbose, "Using TDS 7.x Pre-Login method for the TLS handshake");
            byte[] request = { 0x12, 1, 0, 0x2f, 0, 0, 1, 0, 0, 0, 0x1a, 0, 6, 1, 0, 0x20,
                0, 1, 2, 0, 0x21, 0, 1, 3, 0, 0x22, 0, 4, 4, 0, 0x26, 0, 1, 0xff,
                0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0 };
            transport.Write(request, 0, request.Length);
            byte[] header = new byte[8];
            ReadExact(transport, header, "Unexpected EOF while reading the TDS pre-login response header from " + computer);
            int length = (header[2] << 8 | header[3]) - 8;
            if (length < 0) throw new IOException("Invalid TDS pre-login response length.");
            byte[] response = new byte[length];
            ReadExact(transport, response, "Unexpected EOF while reading the TDS pre-login response payload from " + computer);
            int encrypt = 0;
            for (int offset = 0; offset < response.Length && response[offset] != 255; offset += 5)
            {
                if (offset + 5 > response.Length) throw new IOException("Invalid TDS pre-login response option.");
                if (response[offset] != 1) continue;
                int position = response[offset + 1] << 8 | response[offset + 2];
                if (position >= response.Length) throw new IOException("Invalid TDS pre-login encryption offset.");
                encrypt = response[position] & 15;
                break;
            }
            if (encrypt == 0 || encrypt == 2) throw new InvalidOperationException(string.Format("Server reported an encryption level of 0x{0:X2} which indicates it does not support TDS encryption.", encrypt));
            SslPolicyErrors policy = SslPolicyErrors.None;
            using TdsTlsStream framed = new(transport);
            using SslStream tls = new(framed, true, (sender, certificate, chain, errors) => { policy = errors; return true; });
            TlsMessage(MessageLevel.Verbose, "Starting TLS Handshake");
            tls.AuthenticateAsClient(computer);
            TlsMessage(MessageLevel.Verbose, "TLS result: " + policy);
            // Certificate inspection intentionally returns an untrusted peer certificate, with the pin's warning.
            if (policy != SslPolicyErrors.None) TlsMessage(MessageLevel.Warning, "Client does not trust remote certificate: " + policy);
            X509Certificate2 result = new(tls.RemoteCertificate!);
            TlsMessage(MessageLevel.Verbose, string.Format("Found cert for {0}, Expires: {1}, SANs: {2}", result.Subject, result.NotAfter,
                System.Management.Automation.PSObject.AsPSObject(result).Properties["DnsNameList"]?.Value));
            return result;
        }
    }

    private static void ReadExact(Stream stream, byte[] bytes, string eof)
    {
        int offset = 0;
        while (offset < bytes.Length)
        {
            int count = stream.Read(bytes, offset, bytes.Length - offset);
            if (count == 0) throw new EndOfStreamException(eof);
            offset += count;
        }
    }

    // TDS 7 wraps TLS handshake records in pre-login packets. Stream reads may split any packet.
    private sealed class TdsTlsStream : Stream
    {
        private readonly Stream _inner;
        private int _remaining;
        public TdsTlsStream(Stream inner) { _inner = inner; }
        public override bool CanRead => _inner.CanRead;
        public override bool CanWrite => _inner.CanWrite;
        public override bool CanSeek => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() => _inner.Flush();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override int Read(byte[] buffer, int offset, int count)
        {
            if (count == 0) return 0;
            while (_remaining == 0)
            {
                byte[] header = new byte[8];
                ReadExact(_inner, header, "Unexpected EOF while reading TDS header.");
                _remaining = (header[2] << 8 | header[3]) - 8;
                if (_remaining < 0) throw new IOException("Invalid TDS header length.");
            }
            int read = _inner.Read(buffer, offset, Math.Min(count, _remaining));
            if (read == 0) throw new EndOfStreamException("Unexpected EOF while reading TDS payload.");
            _remaining -= read;
            return read;
        }
        public override void Write(byte[] buffer, int offset, int count)
        {
            while (count > 0)
            {
                int payload = Math.Min(count, 65527);
                int size = payload + 8;
                byte[] packet = new byte[size];
                packet[0] = 0x12;
                packet[1] = (byte)(payload == count ? 1 : 0);
                packet[2] = (byte)(size >> 8);
                packet[3] = (byte)size;
                Buffer.BlockCopy(buffer, offset, packet, 8, payload);
                _inner.Write(packet, 0, packet.Length);
                count -= payload;
                offset += payload;
            }
        }
    }
}
