using System;
using System.Collections.Concurrent;
using System.Net.Sockets;
using System.Text;
using System.Threading;

internal class MpNetClient : IDisposable
{
	public bool IsConnected => _client != null && _client.Connected && _running;
	public string LastError { get; private set; }

	private TcpClient _client;
	private NetworkStream _stream;
	private Thread _readThread;
	private volatile bool _running;
	private readonly ConcurrentQueue<string> _incoming = new ConcurrentQueue<string>();
	private readonly StringBuilder _readBuffer = new StringBuilder();

	// Blocking - call from a background thread, never from Update().
	public void Connect(string host, int port)
	{
		Disconnect();
		try
		{
			_client = new TcpClient();
			_client.NoDelay = true;
			_client.Connect(host, port);
			_stream = _client.GetStream();
			_running = true;
			_readThread = new Thread(ReadLoop) { IsBackground = true };
			_readThread.Start();
			LastError = null;
		}
		catch (Exception e)
		{
			LastError = e.Message;
			Disconnect();
		}
	}

	private void ReadLoop()
	{
		var buf = new byte[8192];
		try
		{
			while (_running)
			{
				int n = _stream.Read(buf, 0, buf.Length);
				if (n <= 0) break;
				_readBuffer.Append(Encoding.UTF8.GetString(buf, 0, n));
				int idx;
				while ((idx = IndexOfNewline(_readBuffer)) >= 0)
				{
					var line = _readBuffer.ToString(0, idx);
					_readBuffer.Remove(0, idx + 1);
					if (line.Length > 0) _incoming.Enqueue(line);
				}
			}
		}
		catch (Exception e)
		{
			LastError = e.Message;
		}
		_running = false;
	}

	private static int IndexOfNewline(StringBuilder sb)
	{
		for (int i = 0; i < sb.Length; i++)
			if (sb[i] == '\n') return i;
		return -1;
	}

	public bool TryDequeue(out string line) => _incoming.TryDequeue(out line);

	public void Send(string json)
	{
		if (!IsConnected) return;
		try
		{
			var bytes = Encoding.UTF8.GetBytes(json + "\n");
			_stream.Write(bytes, 0, bytes.Length);
		}
		catch (Exception e)
		{
			LastError = e.Message;
			_running = false;
		}
	}

	public void Disconnect()
	{
		_running = false;
		try { _stream?.Close(); } catch { }
		try { _client?.Close(); } catch { }
		_stream = null;
		_client = null;
		_readThread = null;
		_readBuffer.Clear();
		while (_incoming.TryDequeue(out _)) { }
	}

	public void Dispose() => Disconnect();
}
