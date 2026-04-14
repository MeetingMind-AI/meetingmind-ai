import asyncio
import websockets
import json


async def test_meeting():
    uri = "ws://localhost:8000/api/ws/ingest/1"
    async with websockets.connect(uri) as websocket:
        messages = [
            {"speaker": "Alice", "text": "Alright team, let's start the daily standup."},
            {"speaker": "Bob", "text": "I finished the frontend UI yesterday."},
            {"speaker": "Alice", "text": "Great. Are there any blockers?"},
            {"speaker": "Bob",
             "text": "Yes, I am blocked because the Vexa API key is missing from our environment variables, so I can't test the audio stream."}
        ]

        for msg in messages:
            print(f"Sending: {msg['text']}")
            await websocket.send(json.dumps(msg))
            await asyncio.sleep(2)  # Wait 2 seconds between messages


asyncio.run(test_meeting())