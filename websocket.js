const websocketUrl = 'ws://localhost:8080';
let websocket;
let reconnectInterval;
const messagesDiv = document.getElementById('messages');
const statusDiv = document.getElementById('status');
const inputAreaDiv = document.getElementById('input-area'); // Get the new input area div

let isPaused = false;
const messageQueue = [];

function appendMessageAndScroll(element) {
    messagesDiv.appendChild(element);
    messagesDiv.scrollTop = messagesDiv.scrollHeight;
}

function processMessage(messageString) {
    try {
        const jsonMessage = JSON.parse(messageString);
        const messageType = jsonMessage.type;
        const messageData = jsonMessage.data;

        // Clear previous input area content before displaying new message types that require input
        if (messageType !== 'line' && messageType !== 'dialogue' && messageType !== 'pause') {
            inputAreaDiv.innerHTML = '';
        }

        switch (messageType) {
            case 'line':
                const lineElement = document.createElement('div');
                lineElement.className = messageData.color === 'secondary' ? 'line-secondary' : 'line-primary';
                lineElement.textContent = messageData.text;
                appendMessageAndScroll(lineElement);
                break;
            case 'prompt':
                const promptContainer = document.createElement('div');
                promptContainer.className = 'prompt-container';

                const promptLabel = document.createElement('span');
                promptLabel.className = 'prompt-label';
                promptLabel.textContent = messageData.label + ' ';
                promptContainer.appendChild(promptLabel);

                const promptInput = document.createElement('input');
                promptInput.type = 'text';
                promptInput.className = 'prompt-input';
                promptInput.placeholder = 'Type your response...';
                promptContainer.appendChild(promptInput);

                promptInput.addEventListener('keypress', (e) => {
                    if (e.key === 'Enter' && promptInput.value !== '') {
                        const response = promptInput.value;
                        websocket.send(response);
                        promptInput.value = ''; // Clear input
                        inputAreaDiv.innerHTML = ''; // Remove prompt after sending
                    }
                });
                inputAreaDiv.appendChild(promptContainer); // Add prompt to input area
                promptInput.focus(); // Focus the input field
                break;
            case 'choices':
                const choiceContainer = document.createElement('div');
                choiceContainer.className = 'choice-container';

                messageData.choices.forEach(choice => {
                    const choiceButton = document.createElement('button');
                    choiceButton.className = 'choice-button';
                    choiceButton.textContent = choice.text;
                    choiceButton.addEventListener('click', () => {
                        websocket.send(choice.key);
                        inputAreaDiv.innerHTML = ''; // Remove choices after selection

                        // Display the sent choice as a dialogue bubble
                        const dialogueContainer = document.createElement('div');
                        dialogueContainer.className = 'dialogue-container action';

                        const dialogueBubble = document.createElement('div');
                        dialogueBubble.className = 'dialogue-bubble';

                        const dialogueText = document.createElement('div');
                        dialogueText.className = 'dialogue-text';
                        dialogueText.textContent = `${choice.text}`; // Only display the text, not key
                        dialogueBubble.appendChild(dialogueText);

                        dialogueContainer.appendChild(dialogueBubble);
                        appendMessageAndScroll(dialogueContainer);

                        // Add 'selected' class to the clicked button for styling
                        choiceButton.classList.add('selected');
                    });
                    choiceContainer.appendChild(choiceButton);
                });
                inputAreaDiv.appendChild(choiceContainer); // Add choices to input area
                break;
            case 'dialogue':
                const dialogueContainer = document.createElement('div');
                dialogueContainer.className = 'dialogue-container';
                if (messageData.name === 'You') {
                    dialogueContainer.classList.add('you');
                }

                const dialogueBubble = document.createElement('div');
                dialogueBubble.className = 'dialogue-bubble';

                const dialogueName = document.createElement('div');
                dialogueName.className = 'dialogue-name';
                dialogueName.textContent = messageData.name;
                dialogueBubble.appendChild(dialogueName);

                const dialogueText = document.createElement('div');
                dialogueText.className = 'dialogue-text';
                dialogueText.textContent = messageData.text;
                dialogueBubble.appendChild(dialogueText);

                dialogueContainer.appendChild(dialogueBubble);
                appendMessageAndScroll(dialogueContainer);
                break;
            case 'pause':
                isPaused = true;
                inputAreaDiv.innerHTML = ''; // Clear input area during pause

                const continueContainer = document.createElement('div');
                continueContainer.className = 'choice-container';
                const continueButton = document.createElement('button');
                continueButton.className = 'choice-button'; // Apply choice-button class
                continueButton.textContent = 'Continue';
                continueButton.addEventListener('click', continueMessages);
                continueContainer.appendChild(continueButton);
                inputAreaDiv.appendChild(continueContainer);

                document.addEventListener('keydown', (e) => {
                    if (isPaused) {
                        e.preventDefault();
                        continueMessages();
                    }
                });

                console.log('Pause message received. Displaying continue button.');
                break;
            case 'blank':
                messagesDiv.innerHTML = ''; // Clear messages area
                console.log('Blank message received, clearing messages area.');
                break;
            case 'quit':
                console.log('Quit message received. Game over or connection closing.');
                inputAreaDiv.innerHTML = ''; // Clear input area
                break;
            default:
                console.warn('Unknown message type:', messageType, messageData);
                const unknownMessageElement = document.createElement('div');
                unknownMessageElement.className = 'message';
                unknownMessageElement.textContent = `Unknown message type: ${messageType} - ${JSON.stringify(messageData)}`;
                messagesDiv.prepend(unknownMessageElement);
                break;
        }
    } catch (e) {
        console.error('Failed to parse message as JSON or handle type:', e);
        const messageElement = document.createElement('div');
        messageElement.className = 'message';
        messageElement.textContent = `Non-JSON or malformed message: ${messageString}`;
        messagesDiv.prepend(messageElement);
    }
}

function connectWebSocket() {
    statusDiv.textContent = 'Status: Connecting...';
    statusDiv.className = 'status connecting';
    websocket = new WebSocket(websocketUrl);

    websocket.onopen = () => {
        console.log('WebSocket Connected');
        statusDiv.textContent = 'Status: Connected';
        statusDiv.className = 'status connected';
        clearInterval(reconnectInterval); // Stop trying to reconnect
        messagesDiv.innerHTML = ''; // Clear messages on connect
    };

    websocket.onmessage = (event) => {
        console.log('Message received:', event.data);
        if (isPaused) {
            messageQueue.push(event.data);
            console.log('Message queued during pause.');
            return;
        }
        processMessage(event.data);
    };

    websocket.onclose = (event) => {
        console.log('WebSocket Disconnected:', event.code, event.reason);
        statusDiv.textContent = 'Status: Disconnected';
        statusDiv.className = 'status disconnected';
        messagesDiv.innerHTML = 'disconnected'; // Display "disconnected" on disconnect
        inputAreaDiv.innerHTML = ''; // Clear input options on disconnect
        // Attempt to reconnect after a delay
        if (!reconnectInterval) {
            reconnectInterval = setInterval(connectWebSocket, 3000); // Try every 3 seconds
        }
    };

    websocket.onerror = (error) => {
        console.error('WebSocket Error:', error);
        statusDiv.textContent = 'Status: Error';
        statusDiv.className = 'status disconnected';
        messagesDiv.innerHTML = 'disconnected'; // Display "disconnected" on error
        websocket.close(); // Close the connection to trigger onclose and reconnection logic
    };
}

function continueMessages() {
    isPaused = false;
    inputAreaDiv.innerHTML = ''; // Clear the continue button
    console.log('Resuming messages. Processing queue until next pause...');
    while (messageQueue.length > 0 && !isPaused) {
        processMessage(messageQueue.shift());
    }
    // Re-focus input if a prompt was displayed before pause
    const currentPromptInput = inputAreaDiv.querySelector('.prompt-input');
    if (currentPromptInput) {
        currentPromptInput.focus();
    }
}