using System;
using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

internal class MpInGameChatHud : MonoBehaviour
{
	private const string ChatKeyPrefsKey = "MpChatKeyBind";

	private Canvas _canvas;
	private CanvasGroup _logGroup;
	private TMP_Text _logText;
	private GameObject _inputRow;
	private TMP_InputField _input;
	private int _lastChatLineCount = -1;
	private bool _chatOpen;
	private int _openedFrame = -1;

	private static Key _chatKey = LoadChatKey();
	public static bool IsRebinding { get; private set; }

	public bool ForceShow;

	private const int MaxVisibleLines = 6;

	public static string ChatKeyName => _chatKey.ToString();

	public static void BeginRebind() => IsRebinding = true;

	private static Key LoadChatKey()
	{
		var name = PlayerPrefs.GetString(ChatKeyPrefsKey, "Enter");
		return Enum.TryParse<Key>(name, out var k) ? k : Key.Enter;
	}

	private static void SetChatKey(Key key)
	{
		_chatKey = key;
		PlayerPrefs.SetString(ChatKeyPrefsKey, key.ToString());
		PlayerPrefs.Save();
	}

	private void Awake()
	{
		BuildUi();
		Debug.Log("[MpInGameChatHud] built, canvas=" + (_canvas != null));
	}

	private void BuildUi()
	{
		var canvasGo = new GameObject("MpChatHud", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
		canvasGo.transform.SetParent(transform, false);
		_canvas = canvasGo.GetComponent<Canvas>();
		_canvas.renderMode = RenderMode.ScreenSpaceOverlay;
		_canvas.sortingOrder = 400;
		var scaler = canvasGo.GetComponent<CanvasScaler>();
		scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
		scaler.referenceResolution = new Vector2(1920, 1080);
		scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;
		scaler.matchWidthOrHeight = 0.5f;

		var logGo = new GameObject("LogPanel", typeof(RectTransform), typeof(CanvasGroup), typeof(Image));
		logGo.transform.SetParent(canvasGo.transform, false);
		var logRt = (RectTransform)logGo.transform;
		logRt.anchorMin = new Vector2(1, 1);
		logRt.anchorMax = new Vector2(1, 1);
		logRt.pivot = new Vector2(1, 1);
		logRt.anchoredPosition = new Vector2(-20, -20);
		logRt.sizeDelta = new Vector2(460, 150);
		logGo.GetComponent<Image>().color = new Color(0f, 0f, 0f, 0.45f);
		_logGroup = logGo.GetComponent<CanvasGroup>();
		_logGroup.alpha = 0f;
		_logGroup.blocksRaycasts = false;
		_logGroup.interactable = false;

		var logTextGo = new GameObject("LogText", typeof(RectTransform));
		logTextGo.transform.SetParent(logGo.transform, false);
		var logTextRt = (RectTransform)logTextGo.transform;
		logTextRt.anchorMin = Vector2.zero;
		logTextRt.anchorMax = Vector2.one;
		logTextRt.offsetMin = new Vector2(10, 8);
		logTextRt.offsetMax = new Vector2(-10, -8);
		_logText = logTextGo.AddComponent<TextMeshProUGUI>();
		_logText.fontSize = 19;
		_logText.alignment = TextAlignmentOptions.BottomRight;
		_logText.enableWordWrapping = true;
		_logText.color = Color.white;
		_logText.outlineWidth = 0.18f;
		_logText.outlineColor = new Color32(0, 0, 0, 255);

		_inputRow = new GameObject("ChatInputRow", typeof(RectTransform), typeof(Image));
		_inputRow.transform.SetParent(canvasGo.transform, false);
		var inputRt = (RectTransform)_inputRow.transform;
		inputRt.anchorMin = new Vector2(1, 1);
		inputRt.anchorMax = new Vector2(1, 1);
		inputRt.pivot = new Vector2(1, 1);
		inputRt.anchoredPosition = new Vector2(-20, -176);
		inputRt.sizeDelta = new Vector2(460, 34);
		_inputRow.GetComponent<Image>().color = new Color(0f, 0f, 0f, 0.6f);

		var textArea = new GameObject("Text Area", typeof(RectTransform));
		textArea.transform.SetParent(_inputRow.transform, false);
		var textAreaRt = (RectTransform)textArea.transform;
		textAreaRt.anchorMin = Vector2.zero;
		textAreaRt.anchorMax = Vector2.one;
		textAreaRt.offsetMin = new Vector2(8, 2);
		textAreaRt.offsetMax = new Vector2(-8, -2);
		textArea.AddComponent<RectMask2D>();

		var textGo = new GameObject("Text", typeof(RectTransform));
		textGo.transform.SetParent(textArea.transform, false);
		var textRt = (RectTransform)textGo.transform;
		textRt.anchorMin = Vector2.zero;
		textRt.anchorMax = Vector2.one;
		textRt.offsetMin = Vector2.zero;
		textRt.offsetMax = Vector2.zero;
		var text = textGo.AddComponent<TextMeshProUGUI>();
		text.fontSize = 18;
		text.color = Color.white;
		text.alignment = TextAlignmentOptions.MidlineLeft;
		text.enableWordWrapping = false;

		var placeholderGo = new GameObject("Placeholder", typeof(RectTransform));
		placeholderGo.transform.SetParent(textArea.transform, false);
		var placeholderRt = (RectTransform)placeholderGo.transform;
		placeholderRt.anchorMin = Vector2.zero;
		placeholderRt.anchorMax = Vector2.one;
		placeholderRt.offsetMin = Vector2.zero;
		placeholderRt.offsetMax = Vector2.zero;
		var placeholderText = placeholderGo.AddComponent<TextMeshProUGUI>();
		placeholderText.text = "Say something...";
		placeholderText.fontSize = 18;
		placeholderText.color = new Color(1f, 1f, 1f, 0.4f);
		placeholderText.fontStyle = FontStyles.Italic;
		placeholderText.alignment = TextAlignmentOptions.MidlineLeft;

		_input = _inputRow.AddComponent<TMP_InputField>();
		_input.textViewport = textAreaRt;
		_input.textComponent = text;
		_input.placeholder = placeholderText;
		_input.text = "";
		_input.onSubmit.AddListener(_ => SendAndClose());
		_inputRow.SetActive(false);
	}

	private void Update()
	{
		if (IsRebinding)
		{
			var kbd = Keyboard.current;
			if (kbd != null)
			{
				foreach (var control in kbd.allKeys)
				{
					if (control.wasPressedThisFrame)
					{
						SetChatKey(control.keyCode);
						IsRebinding = false;
						break;
					}
				}
			}
			return;
		}

		var mgr = MpNetworkManager.Instance;
		bool inLobby = mgr != null && mgr.InLobby;
		bool pauseMenuOpen = (MpNetworkManager.LatestMainBit != null && MpNetworkManager.LatestMainBit.activeInHierarchy)
			|| (MpNetworkManager.LatestMpPanel != null && MpNetworkManager.LatestMpPanel.activeInHierarchy);
		bool inMainMenu = SceneManager.GetActiveScene().name == "MainMenu";
		bool shouldShow = inLobby && !inMainMenu && (!pauseMenuOpen || ForceShow);

		_canvas.enabled = shouldShow;
		if (!shouldShow)
		{
			if (_chatOpen) CloseInput();
			return;
		}

		if (mgr.ChatLines.Count != _lastChatLineCount)
		{
			_lastChatLineCount = mgr.ChatLines.Count;
			var start = Mathf.Max(0, mgr.ChatLines.Count - MaxVisibleLines);
			_logText.text = string.Join("\n", mgr.ChatLines.GetRange(start, mgr.ChatLines.Count - start));
		}

		var kb = Keyboard.current;
		if (kb != null && !_chatOpen && kb[_chatKey].wasPressedThisFrame)
		{
			OpenInput();
		}
		else if (kb != null && _chatOpen && kb.escapeKey.wasPressedThisFrame)
		{
			CloseInput();
		}

		_logGroup.alpha = 1f;
	}

	private void OpenInput()
	{
		_chatOpen = true;
		_openedFrame = Time.frameCount;
		_inputRow.SetActive(true);
		_input.text = "";
		_input.ActivateInputField();
		EventSystem.current.SetSelectedGameObject(_input.gameObject);
	}

	private void CloseInput()
	{
		_chatOpen = false;
		_input.DeactivateInputField();
		_inputRow.SetActive(false);
		if (EventSystem.current != null && EventSystem.current.currentSelectedGameObject == _input.gameObject)
			EventSystem.current.SetSelectedGameObject(null);
	}

	private void SendAndClose()
	{
		if (Time.frameCount == _openedFrame) return;
		var text = _input.text;
		CloseInput();
		if (!string.IsNullOrWhiteSpace(text)) MpNetworkManager.Instance?.SendChat(text);
	}
}
