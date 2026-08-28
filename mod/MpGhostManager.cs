using System.Collections.Generic;
using UnityEngine;

internal static class MpGhostManager
{
	private class GhostEntry
	{
		public GameObject Root;
		public Transform SpriteTransform;
		public Vector3 TargetPos;
		public bool TargetFacingRight;
		public float LastSeenTime;
		public Animator Anim;
		public TextMesh Label;
	}

	private static readonly Dictionary<int, GhostEntry> _ghosts = new Dictionary<int, GhostEntry>();
	private static Transform _spriteTemplate;

	public static void SetTemplate(Transform playerSprite)
	{
		_spriteTemplate = playerSprite;
	}

	public static void ApplySnapshot(List<MpPlayerState> players)
	{
		var seen = new HashSet<int>();
		foreach (var p in players)
		{
			seen.Add(p.id);
			var pos = new Vector3(p.x, p.y, 0f);
			var dotColor = ParseColorOr(p.dotColor, new Color(0.4f, 0.6f, 1f, 0.9f));
			var nameColor = ParseColorOr(p.nameColor, new Color(1f, 1f, 1f, 0.9f));
			if (!_ghosts.TryGetValue(p.id, out var g))
			{
				g = Spawn(p.name, pos, dotColor, nameColor);
				_ghosts[p.id] = g;
			}
			else
			{
				ApplyColors(g, dotColor, nameColor);
			}
			g.TargetPos = pos;
			g.TargetFacingRight = p.facingRight;
			g.LastSeenTime = Time.unscaledTime;
			if (g.Anim != null)
			{
				try { g.Anim.Play(p.animHash, 0, p.animTime); }
				catch (System.Exception e) { Debug.LogWarning($"[Multiplayer] ghost Animator.Play({p.animHash}) failed: {e.Message}"); }
			}
		}

		var stale = new List<int>();
		foreach (var kv in _ghosts)
			if (!seen.Contains(kv.Key)) stale.Add(kv.Key);
		foreach (var id in stale) Remove(id);
	}

	public static void Tick(float dt)
	{
		const float staleTimeout = 6f; // a couple of missed snapshots at the ~2-frame poll rate, comfortably
		var stale = new List<int>();
		foreach (var kv in _ghosts)
		{
			var g = kv.Value;
			if (g.Root == null) { stale.Add(kv.Key); continue; }
			if (Time.unscaledTime - g.LastSeenTime > staleTimeout) { stale.Add(kv.Key); continue; }

			var t = g.Root.transform;
			t.position = Vector3.Lerp(t.position, g.TargetPos, 1f - Mathf.Exp(-14f * dt));

			if (g.SpriteTransform != null)
			{
				var scale = g.SpriteTransform.localScale;
				var sign = g.TargetFacingRight ? 1f : -1f;
				scale.x = Mathf.Abs(scale.x) * sign;
				g.SpriteTransform.localScale = scale;
			}
		}
		foreach (var id in stale) Remove(id);
	}

	private static Color ParseColorOr(string hex, Color fallback)
	{
		if (!string.IsNullOrEmpty(hex) && ColorUtility.TryParseHtmlString(hex, out var c))
		{
			c.a = fallback.a; // callers always want the same fixed ghost/label alpha, not whatever the stored hex implied
			return c;
		}
		return fallback;
	}

	private static void ApplyColors(GhostEntry g, Color dotColor, Color nameColor)
	{
		if (g.Root != null)
			foreach (var partSr in g.Root.GetComponentsInChildren<SpriteRenderer>(true))
				partSr.color = dotColor;
		if (g.Label != null) g.Label.color = nameColor;
	}

	private static GhostEntry Spawn(string name, Vector3 spawnPos, Color dotColor, Color nameColor)
	{
		var root = new GameObject("MPGhost_" + (string.IsNullOrEmpty(name) ? "?" : name));
		Object.DontDestroyOnLoad(root);
		root.transform.position = spawnPos;

		SpriteRenderer sr = null;
		Animator anim = null;
		Transform spriteTransform = null;

		if (_spriteTemplate != null)
		{
			var spriteGo = Object.Instantiate(_spriteTemplate.gameObject, root.transform);
			spriteGo.name = "Sprite";
			spriteGo.transform.localPosition = Vector3.zero;
			foreach (var comp in spriteGo.GetComponentsInChildren<Component>())
			{
				if (comp is Transform || comp is SpriteRenderer || comp is Animator) continue;
				Object.Destroy(comp);
			}
			sr = spriteGo.GetComponent<SpriteRenderer>();
			anim = spriteGo.GetComponent<Animator>();
			spriteTransform = spriteGo.transform;
		}
		else
		{
			sr = root.AddComponent<SpriteRenderer>();
			spriteTransform = root.transform;
		}

		var unlitShader = Shader.Find("Universal Render Pipeline/2D/Sprite-Unlit-Default")
			?? Shader.Find("Sprites/Default");
		foreach (var partSr in root.GetComponentsInChildren<SpriteRenderer>(true))
		{
			if (unlitShader != null) partSr.material = new Material(unlitShader);
			partSr.color = dotColor;
		}

		var labelGo = new GameObject("Label");
		labelGo.transform.SetParent(root.transform);
		labelGo.transform.localPosition = new Vector3(0f, 40f, 0f);
		var tm = labelGo.AddComponent<TextMesh>();
		tm.text = string.IsNullOrEmpty(name) ? "?" : name;
		tm.fontSize = 32;
		tm.characterSize = 1.2f;
		tm.anchor = TextAnchor.LowerCenter;
		tm.alignment = TextAlignment.Center;
		tm.color = nameColor;

		return new GhostEntry
		{
			Root = root,
			SpriteTransform = spriteTransform,
			Label = tm,
			Anim = anim,
			TargetPos = spawnPos,
			LastSeenTime = Time.unscaledTime,
		};
	}

	private static void Remove(int id)
	{
		if (_ghosts.TryGetValue(id, out var g))
		{
			if (g.Root != null) Object.Destroy(g.Root);
			_ghosts.Remove(id);
		}
	}

	public static void Clear()
	{
		foreach (var g in _ghosts.Values)
			if (g.Root != null) Object.Destroy(g.Root);
		_ghosts.Clear();
	}
}
