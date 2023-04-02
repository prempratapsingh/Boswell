//
//  ViewController.swift
//  Boswell
//
//  Created by Ted Barnett (with help from ChatGPT on 3/31/23.
//

import UIKit
import AVFoundation
import Speech

import Foundation



class ViewController: UIViewController, SFSpeechRecognizerDelegate {
    
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var recordButton: UIButton!
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var conversationHistory: [String] = []
    
    // Replace YOUR_API_KEY with your actual OpenAI API key
    let openAI_APIKey = "PASTE_IN_YOUR_OPENAI_API_KEY_HERE"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.textView.layer.borderColor = UIColor.lightGray.cgColor
        self.textView.layer.borderWidth = 1
        
        requestMicrophoneAccess()
        configureSpeechRecognition()
    }
    
    func requestMicrophoneAccess() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Microphone access granted")
                } else {
                    print("Microphone access denied")
                }
            }
        }
    }
    
    func configureSpeechRecognition() {
        speechRecognizer.delegate = self
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized.")
                    self.recordButton.isEnabled = true
                case .denied, .restricted, .notDetermined:
                    print("Speech recognition not authorized.")
                    self.recordButton.isEnabled = false
                @unknown default:
                    print("Unknown speech recognition authorization status.")
                }
            }
        }
    }
    
    func startRecording() {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        let inputNode = audioEngine.inputNode

        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object")
        }

        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false

            if let result = result {
                self.textView.text = result.bestTranscription.formattedString
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.recordButton.isEnabled = true
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        textView.text = "(Listening...)"
    }

    
    @IBAction func recordButtonTapped(_ sender: UIButton) {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recordButton.isEnabled = false
            recordButton.setTitle("Start Recording", for: .normal)
            
            sendToOpenAI(text: textView.text) { response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.textView.text = "Error: \(error.localizedDescription)"
                    } else if let response = response {
                        let userInput = "You: \(self.textView.text ?? "")"
                        let aiResponse = "AI: \(response)"
                        
                        // Append the user input and AI's response to the conversation history
                        self.conversationHistory.append(contentsOf: [userInput, aiResponse])
                        
                        // Update the text view with the full conversation history
                        self.textView.text = self.conversationHistory.joined(separator: "\n")
                        
                        // Speak the AI's response
                        self.speak(text: aiResponse)
                    }
                }
            }
        } else {
            startRecording()
            recordButton.setTitle("Stop Recording", for: .normal)
        }
    }


    func sendToOpenAI(text: String, completion: @escaping (String?, Error?) -> Void) {
        let url = URL(string: "https://api.openai.com/v1/engines/text-davinci-003/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAI_APIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = "You: \(text)\nAI:"
        let requestData: [String: Any] = [
            "prompt": prompt,
            "max_tokens": 150,
            "n": 1,
            "stop": ["\n"],
            "temperature": 0.5
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestData, options: [])
        
        // print("Sending to OpenAI: \(requestData)")

        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error)
            } else if let data = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let text = firstChoice["text"] as? String {
                        completion(text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
                        print("text is: \(text)")
                    } else {
                        // print("Raw response from OpenAI: \(String(data: data, encoding: .utf8) ?? "Unable to decode response")")
                        completion(nil, NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                    }
                } catch {
                    completion(nil, error)
                }
            }
        }
        



        
        task.resume()
    }

    
    func speak(text: String) {
        let speechUtterance = AVSpeechUtterance(string: text)
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechUtterance.rate = 0.5
        speechSynthesizer.speak(speechUtterance)
    }

}
