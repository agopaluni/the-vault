//
//  ClaudeContentTagger.swift
//  The Vault
//
//  Claude implementation of AIContentTagger. Sends 1–3 downsampled keyframes to
//  the Messages API (claude-haiku-4-5 — cheapest vision model) with Structured
//  Outputs so the reply is guaranteed-parseable JSON. Raw HTTPS via URLSession
//  (there is no official Anthropic Swift SDK). Synchronous per call; the
//  enrichment service runs several in parallel for speed.
//

import Foundation

struct ClaudeContentTagger: AIContentTagger {
    let modelName = "claude-haiku-4-5"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func tag(keyframes: [Data], mediaKind: MediaKind, apiKey: String) async throws -> AITagResult {
        guard !keyframes.isEmpty else { throw AITaggerError.noKeyframes }

        var content: [[String: Any]] = keyframes.map { data in
            ["type": "image",
             "source": ["type": "base64",
                        "media_type": "image/jpeg",
                        "data": data.base64EncodedString()]]
        }
        content.append(["type": "text", "text": Self.userPrompt(for: mediaKind)])

        let body: [String: Any] = [
            "model": modelName,
            "max_tokens": 300,
            "system": Self.systemPrompt,
            "output_config": ["format": ["type": "json_schema", "schema": Self.schema]],
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AITaggerError.badResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw AITaggerError.invalidKey }
            throw AITaggerError.api(http.statusCode, Self.errorMessage(from: data))
        }
        return try parse(data)
    }

    // MARK: - Parsing

    private func parse(_ data: Data) throws -> AITagResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let inner = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: inner) as? [String: Any]
        else { throw AITaggerError.badResponse }

        let rawTags = parsed["contentTags"] as? [String] ?? []
        let tags = Set(rawTags.compactMap { ContentTag(rawValue: $0) })
        return AITagResult(contentTags: tags,
                           sceneDescription: parsed["sceneDescription"] as? String,
                           confidence: parsed["confidence"] as? Double)
    }

    private static func errorMessage(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let message = error["message"] as? String else { return "unknown" }
        return message
    }

    // MARK: - Prompt & schema

    private static let systemPrompt =
    """
    You are a footage-logging assistant for a filmmaker. Given a few frames from \
    one clip, classify the shot using ONLY these content tags:
    - talkingHead: a person's face is the subject, addressing camera.
    - bRoll: establishing / landscape / object / cutaway with no primary subject speaking.
    - inMotion: the camera is clearly handheld or moving.
    - driving: shot from inside or of a moving vehicle.
    - dialoguePresent: people are likely talking / conversation implied.
    - silent: no implied speech.
    Choose every tag that applies. Be conservative — only include a tag you are \
    reasonably confident about. Respond strictly in the required JSON schema.
    """

    private static func userPrompt(for kind: MediaKind) -> String {
        "These are keyframes from a single \(kind == .video ? "video clip" : "photo"). "
        + "Return the applicable content tags, a short scene description, and your confidence (0–1)."
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "contentTags": [
                "type": "array",
                "items": ["type": "string",
                          "enum": ContentTag.allCases.map(\.rawValue)]
            ],
            "sceneDescription": ["type": "string"],
            "confidence": ["type": "number"]
        ],
        "required": ["contentTags", "sceneDescription", "confidence"],
        "additionalProperties": false
    ]
}
