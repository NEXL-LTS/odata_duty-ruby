# Model Context Protocol Crash Course: Key Concepts and Terminology

The [Model Context Protocol](https://modelcontextprotocol.io) (MCP) is an open protocol that enables seamless integration between LLM applications and external data sources and tools. Here's a quick overview of the core concepts:

## 1. Architecture Components

- **Host:**  
  The application that initiates connections and coordinates between clients and LLMs. Hosts manage multiple clients, enforce security policies, and handle user authorization.
  
- **Client:**  
  A connector within the host application that maintains a 1:1 relationship with a server. Clients establish stateful sessions, handle protocol negotiation, and route messages.

- **Server:**  
  A service that provides context and capabilities to LLM applications. Servers expose resources, tools, and prompts while operating independently with focused responsibilities.

## 2. Core Primitives

- **Resources:**  
  Structured data or content that provides additional context to the language model. Resources are application-controlled and represent contextual information like file contents, database records, or API results.
  
- **Prompts:**  
  Pre-defined templates or instructions that guide language model interactions. Prompts are user-controlled and represent interactive elements like slash commands or menu options.
  
- **Tools:**  
  Executable functions that allow models to perform actions or retrieve information. Tools are model-controlled and represent capabilities like API requests, data transformations, or file operations.

- **Sampling:**  
  A client-side feature that enables server-initiated agentic behaviors and recursive LLM interactions. Sampling allows servers to request LLM processing while maintaining appropriate security boundaries.

## 3. Protocol Mechanics

- **Base Protocol:**  
  MCP uses [JSON-RPC](https://www.jsonrpc.org/) 2.0 as its message format, supporting three types of messages:
  - **Requests:** Bidirectional messages expecting a response
  - **Responses:** Successful results or errors matching specific request IDs
  - **Notifications:** One-way messages requiring no response
  
- **Capability Negotiation:**  
  Clients and servers explicitly declare their supported features during initialization. This determines which protocol primitives are available during a session.

- **Lifecycle Management:**  
  The protocol manages connection initialization, capability exchange, and session control to maintain a stateful connection between clients and servers.

## 4. Key Design Principles

- Servers should be extremely easy to build
- Servers should be highly composable
- Servers should not be able to read the whole conversation or "see into" other servers
- Features can be added to servers and clients progressively

## Summary

- **Host Applications** create and manage multiple **Clients**, each connecting to a specific **Server**
- **Resources**, **Prompts**, and **Tools** are the fundamental primitives servers expose
- The protocol uses **JSON-RPC** messages for standardized communication
- **Capability negotiation** ensures clients and servers understand supported functionality
- Strong **security boundaries** protect user data and ensure appropriate consent
- MCP enables powerful AI integrations while maintaining control and security

