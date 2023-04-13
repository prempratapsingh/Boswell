//
//  ViewController.swift
//  Boswell
//
//  Created by Ted Barnett (with help from ChatGPT-4!) on 3/31/2023.
//
// CODE SUMMARY (from ChatGPT-4):
// Imports necessary libraries like UIKit, AVFoundation, Speech, and Foundation.
// Sets up the ViewController class and its delegates for speech recognition.
// Initializes and configures the speech recognizer, audio engine, and speech synthesizer.
// Requests microphone access and configures speech recognition in viewDidLoad().
// Implements the startRecording() function to start recording user speech.
// Defines the recordButtonTapped() function, which toggles the recording state and sends the recorded speech to the ChatGPT API.
// Creates the sendToOpenAI() function to send a POST request to the ChatGPT API, which returns the AI-generated response.
// Implements the speak() function to convert the AI-generated text response into speech.
//

import UIKit
import AVFoundation
import Speech
import Foundation

class ViewController: UIViewController, SFSpeechRecognizerDelegate {
    
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var listeningStatus: UILabel!
    @IBOutlet weak var clearButton:UIButton!
    //@IBOutlet weak var recordingText: UITextView!
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    public let speechSynthesizer = AVSpeechSynthesizer()
    private var conversationHistory: [NSAttributedString] = []

    // let openAI_APIKey = "PASTE_IN_YOUR_OPENAI_API_KEY_HERE" // old in-line version (replaced below)
    // Load the OpenAI API key from the "openAI_APIKey.plist" file in the project's bundle.
    // If it fails to load the key, it will throw a fatal error. Otherwise, it will return the loaded API key as a string
    // Eventually replace this with a request from the user for their OpenAPI key, and save that in the openAI_APIKey.plist file.
    let openAI_APIKey: String = {
        guard let plistPath = Bundle.main.path(forResource: "openAI_APIKey", ofType: "plist"),
            let plistDict = NSDictionary(contentsOfFile: plistPath),
            let apiKey = plistDict["APIKey"] as? String else {
                fatalError("Failed to load OpenAI API key from 'openAI_APIKey.plist'")
        }
        return apiKey
    }()

    
    override func viewDidLoad() { //viewDidLoad
        super.viewDidLoad()
        
        requestMicrophoneAccess()
        configureSpeechRecognition()
        
        // Debugging iOS voice problem
        let voices = AVSpeechSynthesisVoice.speechVoices()
        print("Voice Count: \(voices.count)")
        
        //recordingText.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        //recordingText.isHidden = true
        
        
        if traitCollection.userInterfaceStyle == .dark {
            // iPhone is in Dark Mode
        } else {
            // iPhone is in Light Mode
        }

        
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
                // TODO: Ensure font color is blue
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

        listeningStatus.text = "Listening..."
        //recordingText.text = "" // clear prior text
        //recordingText.isHidden = false
    }

    
    @IBAction func recordButtonTapped(_ sender: UIButton) {
        // Check if the audio engine is running (i.e., currently recording)
        if audioEngine.isRunning {
            // Stop the audio engine and end the recognition request
            audioEngine.stop()
            recognitionRequest?.endAudio()
            // Disable the record button temporarily
            recordButton.isEnabled = false
            // Update the record button title to indicate recording has stopped
            recordButton.setTitle("Start Recording", for: .normal)

            // Send the recorded speech to the ChatGPT API
            sendToChatGPT(text: textView.text) { response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.textView.text = "Error: \(error.localizedDescription)"
                    } else if let response = response {
                        self.appendConversation(userInput: self.textView.text ?? "", aiResponse: response)

                        self.listeningStatus.text = "" // clear the listening status text field

                        // Speak the AI's response
                        self.speak(text: response)
                    }
                }
            }
        } else {
            // Start recording user speech
            startRecording()
            // Update the record button title to indicate recording has started
            recordButton.setTitle("Stop Recording", for: .normal)
        }
    }

    // Appends conversation text to textView
    func appendConversation(userInput: String, aiResponse: String) {
        // Remove "You: " and "AI: " from the userInput and aiResponse strings
        let userInputNoPrefix = userInput.replacingOccurrences(of: "You: ", with: "")
        let aiResponseNoPrefix = aiResponse.replacingOccurrences(of: "AI: ", with: "")

        // Append the formatted user input and AI's response to the conversation history
        let font = UIFont.systemFont(ofSize: 24)
        let attributesAIText: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.lightGray, .font: UIFont.boldSystemFont(ofSize: 24)]

        let attributesUserText: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.blue, .font: UIFont.boldSystemFont(ofSize: 24)]

        let formattedUserInput = NSAttributedString(string: userInputNoPrefix + "\n", attributes: attributesUserText)
        let formattedAIResponse = NSAttributedString(string: aiResponseNoPrefix + "\n\n", attributes: attributesAIText)
        self.conversationHistory.append(contentsOf: [formattedUserInput, formattedAIResponse])

        // Update the text view with the full conversation history
        let fullHistory = NSMutableAttributedString()
        for item in self.conversationHistory {
            fullHistory.append(item)
        }
        self.textView.attributedText = fullHistory // append this new prompt and response to the textView
        // Then scroll to bottom of textView per https://developer.apple.com/forums/thread/126549 (Swift 5)
        let range = NSMakeRange(self.textView.text.count - 1, 0)
        self.textView.scrollRangeToVisible(range)
    }


// Sends to OpenAI API, currently using GPT-3 model
    func sendToChatGPT(text: String, completion: @escaping (String?, Error?) -> Void) {
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
        
        self.listeningStatus.text = "Thinking..."

        
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
                        print("Raw response from OpenAI: \(String(data: data, encoding: .utf8) ?? "Unable to decode response")")
                        completion(nil, NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                    }
                } catch {
                    completion(nil, error)
                }
            }
        }
        task.resume()
    }
    
    @IBAction func clearButtonTapped(_ sender: UIButton) {
        self.textView.text = "" // clear the text area if clearButton pressed
        listeningStatus.text = "Cleared screen"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.listeningStatus.text = ""
        }
    }
    
    func speak(text: String) {
        let speechUtterance = AVSpeechUtterance(string: text)
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechUtterance.rate = 0.5
        speechSynthesizer.speak(speechUtterance)
    }
}
