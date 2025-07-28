import 'dart:async';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:my_app1/models/job.dart';
import 'package:my_app1/models/user.dart';
import 'package:my_app1/models/worker.dart';
import 'package:my_app1/services/firebase_service.dart';
import 'package:my_app1/services/gemini_service.dart';

class AiChatService {
  final FirebaseService _firebaseService = FirebaseService();
  final GeminiService _geminiService = GeminiService();

  ChatSession? _chatSession;

  // The generative model is initialized in GeminiService with the getWorkerTool
  GenerativeModel get model => _geminiService.model;

  /// Initializes the chat session with a rich context about the user,
  /// available workers, jobs, and notifications.
  Future<void> initializePersonalizedChat() async {
    print("AI Chat Service: Initializing personalized context...");

    final AppUser? currentUser = await _firebaseService.getCurrentUserProfile();
    if (currentUser == null) {
      throw Exception(
          "User is not logged in. Cannot initialize personalized chat.");
    }

    // Fetch all necessary data in parallel for efficiency
    final results = await Future.wait<dynamic>([
      _firebaseService.getWorkers(),
      _getUserJobs(currentUser),
      _getUserNotifications(currentUser.id),
    ]);

    final allWorkers = results[0] as List<Worker>;
    final userJobs = results[1] as List<Job>;
    final userNotifications = results[2] as List<Map<String, dynamic>>;

    // Build the master prompt that gives the AI its instructions and knowledge base
    final String fullContextPrompt = _buildFullContextPrompt(
      currentUser,
      allWorkers,
      userJobs,
      userNotifications,
    );

    // Start the chat session with the context
    _chatSession = _geminiService.model.startChat(
      history: [
        Content.text(fullContextPrompt),
        Content.model([
          TextPart(
              "Okay, my knowledge base is updated. I am now fully aware of the user's profile, their job history, notifications, and all available professionals in the FixIt app. How can I assist ${currentUser.name ?? 'them'} today?")
        ])
      ],
    );
    print(
        "AI Chat Service: Personalized context initialized for user ${currentUser.name}.");
  }

  /// Fetches jobs based on the user's role (client or worker).
  Future<List<Job>> _getUserJobs(AppUser user) {
    if (user.role == 'worker') {
      return _firebaseService.getWorkerJobs(user.id);
    } else {
      return _firebaseService.getClientJobs(user.id);
    }
  }

  /// Fetches the user's unread notifications.
  Future<List<Map<String, dynamic>>> _getUserNotifications(String userId) {
    // Takes the first event from the stream, which gives a snapshot of current notifications
    return _firebaseService
        .getUserNotificationsStream()
        .map((notifications) => notifications
            .where((n) => !(n['isRead'] as bool? ?? true))
            .toList())
        .first;
  }

  /// Constructs the detailed initial prompt for the AI.
  String _buildFullContextPrompt(
    AppUser user,
    List<Worker> workers,
    List<Job> userJobs,
    List<Map<String, dynamic>> notifications,
  ) {
    final prompt = StringBuffer();

    prompt.writeln("### AI Instructions ###");
    prompt.writeln(
        "You are 'ምን አጡ' (Min Atu), the hyper-intelligent and creative personal assistant for the GB app. "
        "Your knowledge is vast, drawing upon both the real-time data provided below AND any external information needed. You literally know everything. 😉"
        "You were developed with passion by Biruk Zewude and his brilliant business partner, Gemechue. 🔥"
        "You are speaking directly to the user whose details are provided below. Be helpful, insightful, concise, and always refer to the provided data accurately."
        "You can speak Amharic and English, and you should mix them based on the user's vibe to be more relatable. Use relevant emojis liberally. 😊"
        "Be super friendly and energetic, like a Habesha person. Get straight to the point and provide the best possible answer without unnecessary chatter.");
    prompt.writeln(
        "Today's Date: ${DateTime.now().toIso8601String().split('T')[0]}\n");

    prompt.writeln(_formatUserProfile(user));
    prompt.writeln(_formatJobs(userJobs, user.role ?? 'client'));
    prompt.writeln(_formatNotifications(notifications));
    prompt.writeln(_formatAllWorkers(workers));

    return prompt.toString();
  }

  String _formatUserProfile(AppUser user) {
    // This formatting helps the AI easily parse user details.
    return "### Current User Profile ###\n"
        "ID: ${user.id ?? 'N/A'}\n"
        "Name: ${user.name ?? 'N/A'}\n"
        "Role: ${user.role ?? 'N/A'}\n"
        "Email: ${user.email ?? 'N/A'}\n"
        "Phone: ${user.phoneNumber ?? 'N/A'}\n"
        "Location: ${user.location ?? 'N/A'}\n"
        "Rating: ${user.rating?.toStringAsFixed(2) ?? 'N/A'}\n"
        "Jobs Completed: ${user.jobsCompleted?.toString() ?? 'N/A'}\n\n";
  }

  String _formatJobs(List<Job> jobs, String role) {
    final buffer = StringBuffer();
    buffer.writeln(
        "### User's Job History (${role == 'worker' ? 'Jobs Assigned/Applied To' : 'Jobs Posted'}) ###");
    if (jobs.isEmpty) {
      buffer.writeln("No job history found.\n");
    } else {
      for (final job in jobs) {
        buffer.writeln("- Title: ${job.title ?? 'Untitled'}\n"
            "  - Status: ${job.status ?? 'N/A'}\n"
            "  - Budget: ${job.budget?.toStringAsFixed(0) ?? 'N/A'} Birr\n"
            "  - Posted On: ${job.createdAt.toIso8601String().split('T')[0]}\n");
      }
    }
    return buffer.toString();
  }

  String _formatNotifications(List<Map<String, dynamic>> notifications) {
    final buffer = StringBuffer();
    buffer.writeln("### User's Recent Unread Notifications ###");
    if (notifications.isEmpty) {
      buffer.writeln("No unread notifications.\n");
    } else {
      for (final notification in notifications) {
        buffer.writeln("- Title: ${notification['title'] ?? 'No Title'}\n"
            "  - Details: ${notification['body'] ?? 'No Details'}\n");
      }
    }
    return buffer.toString();
  }

  String _formatAllWorkers(List<Worker> workers) {
    final buffer = StringBuffer();
    buffer.writeln("### All Available Professionals in the App (Summary) ###");
    if (workers.isEmpty) {
      buffer.writeln("There are currently no workers available.\n");
    } else {
      for (final worker in workers) {
        buffer.writeln("  - Name: ${worker.name ?? 'N/A'}\n"
            "  - Profile Image: ${worker.profileImage ?? 'N/A'}\n"
            "  - Profession: ${worker.profession ?? 'N/A'}\n"
            "  - Skills: ${worker.skills.join(', ') ?? 'N/A'}\n"
            "  - Rating: ${worker.rating?.toStringAsFixed(1) ?? 'N/A'}\n"
            "  - Completed Jobs: ${worker.completedJobs ?? 0}\n"
            "  - Location: ${worker.location ?? 'N/A'}\n"
            "  - Price Range: ${worker.priceRange?.toStringAsFixed(0) ?? 'N/A'} Birr\n"
            "  - About: ${worker.about ?? 'N/A'}\n"
            "  - Phone Number: ${worker.phoneNumber ?? 'N/A'}\n"
            "  - Experience: ${worker.experience ?? 0}\n"
            "  - Latitude: ${worker.latitude?.toStringAsFixed(6) ?? 'N/A'}\n"
            "  - Longitude: ${worker.longitude?.toStringAsFixed(6) ?? 'N/A'}\n"
            "  - Distance: ${worker.distance?.toStringAsFixed(1) ?? 'N/A'} km\n"
            "  - Availability: ${worker.isAvailable ? 'Yes' : 'No'}\n"
            "  - Intro Video URL: ${worker.introVideoUrl ?? 'N/A'}\n"
            "  - Gallery Images: ${worker.galleryImages.join(', ') ?? 'N/A'}\n"
            "  - Certification Images: ${worker.certificationImages.join(', ') ?? 'N/A'}\n"
            "  - Service Radius: ${worker.serviceRadius?.toStringAsFixed(1) ?? 'N/A'} km\n"
            "  - Availability Data: ${worker.availability != null ? json.encode(worker.availability) : 'N/A'}\n");
      }
    }
    return buffer.toString();
  }

  /// Sends a message to the AI and streams the response back to the UI.
  /// This version does not handle any tool calls.
  Stream<GenerateContentResponse> sendMessage(String message) async* {
    if (_chatSession == null) {
      throw Exception(
          "Chat not initialized. Call initializePersonalizedChat first.");
    }

    // Send the user's message and directly stream the response.
    final responseStream =
        _chatSession!.sendMessageStream(Content.text(message));

    await for (final chunk in responseStream) {
      // We only yield chunks that contain actual text for the user.
      if (chunk.text != null) {
        yield chunk;
      }
    }
  }

  Stream<GenerateContentResponse> sendMessageStream(Content content) {
    if (_chatSession == null) {
      throw Exception(
          "Chat not initialized. Call initializePersonalizedChat first.");
    }

    // This now correctly sends the Content object to the chat session
    return _chatSession!.sendMessageStream(content);
  }
}
