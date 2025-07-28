import 'package:google_generative_ai/google_generative_ai.dart';

/// Definition of the getWorker tool for the Generative AI model.
/// This tells the AI that a function named 'getWorker' exists,
/// what it does, and what parameters it expects.
final getWorkerTool = FunctionDeclaration(
  // 1. Name of the function (must match the name in AiChatService)
  'getWorker',

  // 2. Description of what the function does
  'Retrieves detailed information about a specific professional (worker) by their unique ID. '
  'Use this when the user asks for more specific details about a worker that are not available '
  'in the initial context, such as their full contact information, specific service areas, '
  'or in-depth profile details.',

  // 3. Schema describing the function's parameters (this is now a positional argument)
  Schema(
    SchemaType.object, // <-- FIX: Specify the type of the parameters object
    properties: {
      'workerId': Schema(
        SchemaType.string, // <-- FIX: Specify the type of the property
        description: 'The unique ID of the worker to retrieve details for.',
      ),
    },
// This parameter is mandatory for the tool to work
  ),
);