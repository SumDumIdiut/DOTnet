using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

internal static class MpMenuBuilder
{
	public static void Install(pauseMenuScript menu)
	{
		MpNetworkManager.GetOrCreate();

		if (menu.mainBitPublic == null || menu.settingsBitPublic == null) return;
		if (menu.mainBitPublic.transform.Find("Multiplayer") != null) return;

		var settingsButton = menu.mainBitPublic.transform.Find("Settings");
		var quitButton = menu.mainBitPublic.transform.Find("QuitToDesktop");
		if (settingsButton == null || quitButton == null) return;

		var mpButtonGo = Object.Instantiate(settingsButton.gameObject, settingsButton.parent);
		mpButtonGo.name = "Multiplayer";
		var mpButtonRt = (RectTransform)mpButtonGo.transform;
		var quitRt = (RectTransform)quitButton;
		var settingsRt = (RectTransform)settingsButton;
		var rowSpacing = settingsRt.anchoredPosition.y - quitRt.anchoredPosition.y;
		var originalQuitY = quitRt.anchoredPosition.y;

		var background = menu.mainBitPublic.GetComponent<RectTransform>();
		if (background != null)
		{
			// resizing shifts the box's center, so every child's local offset needs the same compensation
			var halfShift = rowSpacing / 2f;
			foreach (Transform child in menu.mainBitPublic.transform)
			{
				if (child == quitRt || child == mpButtonRt) continue;
				var childRt = child as RectTransform;
				if (childRt == null) continue;
				childRt.anchoredPosition = new Vector2(childRt.anchoredPosition.x, childRt.anchoredPosition.y + halfShift);
			}
			quitRt.anchoredPosition = new Vector2(quitRt.anchoredPosition.x, originalQuitY - halfShift);
			mpButtonRt.anchoredPosition = new Vector2(quitRt.anchoredPosition.x, originalQuitY + halfShift);

			background.sizeDelta = new Vector2(background.sizeDelta.x, background.sizeDelta.y + rowSpacing);
			background.anchoredPosition = new Vector2(background.anchoredPosition.x, background.anchoredPosition.y - halfShift);

			var dividerTemplate = FindAnyDivider(menu.mainBitPublic.transform);
			if (dividerTemplate != null)
			{
				var newDivider = Object.Instantiate(dividerTemplate.gameObject, dividerTemplate.parent);
				newDivider.name = "Line (Multiplayer-Quit)";
				var newDividerRt = (RectTransform)newDivider.transform;
				newDividerRt.anchoredPosition = new Vector2(newDividerRt.anchoredPosition.x, (mpButtonRt.anchoredPosition.y + quitRt.anchoredPosition.y) / 2f);
			}
		}

		SetButtonLabel(mpButtonGo, "Multiplayer");
		var mpButton = mpButtonGo.GetComponent<Button>();
		mpButton.onClick = new Button.ButtonClickedEvent();

		var mpPanel = BuildPanel(menu, backTarget: menu.mainBitPublic);
		mpButton.onClick.AddListener(() =>
		{
			menu.mainBitPublic.SetActive(false);
			mpPanel.SetActive(true);
		});

		MpNetworkManager.LatestMainBit = menu.mainBitPublic;
		MpNetworkManager.LatestMpPanel = mpPanel;
	}

	private static Transform FindAnyDivider(Transform parent)
	{
		foreach (Transform child in parent)
			if (child.name.StartsWith("Line")) return child;
		return null;
	}

	private static void SetButtonLabel(GameObject buttonGo, string text)
	{
		var label = buttonGo.transform.Find("Text (TMP)");
		if (label == null) return;
		var loc = label.GetComponent<UnityEngine.Localization.Components.LocalizeStringEvent>();
		if (loc != null) Object.Destroy(loc);
		var tmp = label.GetComponent<TMP_Text>();
		if (tmp != null) tmp.text = text;
	}

	private static GameObject BuildPanel(pauseMenuScript menu, GameObject backTarget)
	{
		var clone = Object.Instantiate(menu.settingsBitPublic, menu.settingsBitPublic.transform.parent);
		clone.name = "MultiplayerBit";
		clone.SetActive(false);

		var settingsScript = clone.GetComponent<SettingsScript>();
		if (settingsScript != null) Object.Destroy(settingsScript);

		Transform title = null;
		var toDestroy = new List<GameObject>();
		foreach (Transform child in clone.transform)
		{
			if (child.name == "Settings") { title = child; continue; }
			toDestroy.Add(child.gameObject);
		}
		foreach (var go in toDestroy) Object.Destroy(go);

		TMP_FontAsset font = null;
		if (title != null)
		{
			var titleTmp = title.GetComponent<TMP_Text>();
			if (titleTmp != null) { titleTmp.text = "Multiplayer"; font = titleTmp.font; }
			var loc = title.GetComponent<UnityEngine.Localization.Components.LocalizeStringEvent>();
			if (loc != null) Object.Destroy(loc);

			var closeBtn = title.Find("Close");
			if (closeBtn != null)
			{
				SetButtonLabel(closeBtn.gameObject, "Back");
				var btn = closeBtn.GetComponent<Button>();
				btn.onClick = new Button.ButtonClickedEvent();
				btn.onClick.AddListener(() =>
				{
					clone.SetActive(false);
					backTarget.SetActive(true);
				});
			}
		}

		var ui = clone.AddComponent<MpPanelUI>();
		ui.Build(clone, font, settingsButtonTemplate: menu.mainBitPublic.transform.Find("Settings").gameObject);
		return clone;
	}
}
