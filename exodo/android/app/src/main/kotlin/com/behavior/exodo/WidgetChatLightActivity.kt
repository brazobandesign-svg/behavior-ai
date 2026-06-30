package com.behavior.exodo

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText

class WidgetChatLightActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_widget_chat_light)

        val root = findViewById<View>(R.id.overlay_root)
        val container = findViewById<View>(R.id.overlay_container)
        val logoBtn = findViewById<View>(R.id.overlay_logo_btn)
        val sendBtn = findViewById<View>(R.id.overlay_send_btn)
        val input = findViewById<EditText>(R.id.overlay_input)

        root.setOnClickListener { finish() }
        container.setOnClickListener { }

        sendBtn.alpha = 0.5f

        input.requestFocus()
        input.postDelayed({
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
        }, 100)

        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                if (!s.isNullOrBlank()) {
                    sendBtn.alpha = 1.0f
                } else {
                    sendBtn.alpha = 0.5f
                }
            }
            override fun afterTextChanged(s: Editable?) {}
        })

        logoBtn.setOnClickListener {
            openAppNormal()
        }

        sendBtn.setOnClickListener {
            val text = input.text.toString().trim()
            if (text.isNotEmpty()) {
                sendAndOpenApp(text)
            }
        }

        input.setOnEditorActionListener { _, actionId, event ->
            if (actionId == EditorInfo.IME_ACTION_SEND ||
                (event != null && event.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)) {
                val text = input.text.toString().trim()
                if (text.isNotEmpty()) {
                    sendAndOpenApp(text)
                }
                true
            } else {
                false
            }
        }
    }

    private fun sendAndOpenApp(prompt: String) {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(currentFocus?.windowToken, 0)

        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("widget_prompt", prompt)
        }
        startActivity(intent)
        finish()
    }

    private fun openAppNormal() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(currentFocus?.windowToken, 0)

        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(intent)
        finish()
    }
}
