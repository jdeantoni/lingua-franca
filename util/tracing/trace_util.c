/**
 * @file
 * @author Edward A. Lee
 *
 * @section LICENSE
Copyright (c) 2020, The University of California at Berkeley

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 * @section DESCRIPTION
 * Standalone program to convert a Lingua Franca trace file to a comma-separated values
 * text file.
 */
#define LINGUA_FRANCA_TRACE
#include "reactor.h"
#include "trace.h"
#include "trace_util.h"

/** Buffer for reading object descriptions. Size limit is BUFFER_SIZE bytes. */
char buffer[BUFFER_SIZE];

/** Buffer for reading trace records. */
trace_record_t trace[TRACE_BUFFER_CAPACITY];

/** The start time read from the trace file. */
instant_t start_time;

/** Name of the top-level reactor (first entry in symbol table). */
char* top_level = NULL;

/** Table of pointers to the self struct of a reactor. */
// FIXME: Replace with hash table implementation.
object_description_t* object_table;
int object_table_size = 0;

/**
 * Get the reactor name whose self struct is the specified pointer.
 * If there is no such reactor, return NULL.
 * If the index argument is non-null, then put the index
 * of the reactor in the table into the int pointed to
 * or -1 if none was found.
 * @param reactor The pointer to a self struct.
 * @param index An optional pointer into which to write the index.
 */
char* get_reactor_name(void* reactor, int* index) {
    // FIXME: Replace with a hash table implementation.
    for (int i = 0; i < object_table_size; i++) {
        if (object_table[i].reactor == reactor && object_table[i].type == trace_reactor) {
            if (index != NULL) {
                *index = i;
            }
            return object_table[i].description;
        }
    }
    if (index != NULL) {
        *index = 0;
    }
    return NULL;
}

/**
 * Get the trigger name for the specified pointer.
 * If there is no such trigger, return NULL.
 * If the index argument is non-null, then put the index
 * of the trigger in the table into the int pointed to
 * or -1 if none was found.
 * @param reactor The pointer to a self struct.
 * @param index An optional pointer into which to write the index.
 */
char* get_trigger_name(void* trigger, int* index) {
    // FIXME: Replace with a hash table implementation.
    for (int i = 0; i < object_table_size; i++) {
        if (object_table[i].trigger == trigger && object_table[i].type == trace_trigger) {
            if (index != NULL) {
                *index = i;
            }
            return object_table[i].description;
        }
    }
    if (index != NULL) {
        *index = 0;
    }
    return NULL;
}

/**
 * Print the object to description table.
 */
void print_table() {
    printf("------- objects traced:\n");
    for (int i = 0; i < object_table_size; i++) {
        char* type = "reactor";
        if (object_table[i].type == trace_trigger) {
            type = "trigger";
        }
        printf("reactor = %p, trigger = %p, type = %s: %s\n", 
            object_table[i].reactor,
            object_table[i].trigger,
            type,
            object_table[i].description);
    } 
    printf("-------\n");
}

/**
 * Read header information.
 * @return The number of objects in the object table or -1 for failure.
 */
size_t read_header(FILE* trace_file) {
    // Read the start time.
    int items_read = fread(&start_time, sizeof(instant_t), 1, trace_file);
    if (items_read != 1) _LF_TRACE_FAILURE(trace_file);

    printf("Start time is %lld.\n", start_time);

    // Read the table mapping pointers to descriptions.
    // First read its length.
    items_read = fread(&object_table_size, sizeof(int), 1, trace_file);
    if (items_read != 1) _LF_TRACE_FAILURE(trace_file);

    printf("There are %d objects traced.\n", object_table_size);

    object_table = calloc(object_table_size, sizeof(trace_record_t));
    if (object_table == NULL) {
        fprintf(stderr, "ERROR: Memory allocation failure %d.\n", errno);
        return -1;
    }

    // Next, read each table entry.
    for (int i = 0; i < object_table_size; i++) {
        void* reactor;
        items_read = fread(&reactor, sizeof(void*), 1, trace_file);
        if (items_read != 1) _LF_TRACE_FAILURE(trace_file);
        object_table[i].reactor = reactor;

        void* trigger;
        items_read = fread(&trigger, sizeof(trigger_t*), 1, trace_file);
        if (items_read != 1) _LF_TRACE_FAILURE(trace_file);
        object_table[i].trigger = trigger;

        // Next, read the type.
        _lf_trace_object_t trace_type;
        items_read = fread(&trace_type, sizeof(_lf_trace_object_t), 1, trace_file);
        if (items_read != 1) _LF_TRACE_FAILURE(trace_file);
        object_table[i].type = trace_type;

        // Next, read the string description into the buffer.
        int description_length = 0;
        char character;
        items_read = fread(&character, sizeof(char), 1, trace_file);
        if (items_read != 1) _LF_TRACE_FAILURE(trace_file);
        while(character != 0 && description_length < BUFFER_SIZE - 1) {
            buffer[description_length++] = character;
            items_read = fread(&character, sizeof(char), 1, trace_file);
            if (items_read != 1) _LF_TRACE_FAILURE(trace_file);
        }
        // Terminate with null.
        buffer[description_length++] = 0;

        // Allocate memory to store the description.
        object_table[i].description = malloc(description_length);
        strcpy(object_table[i].description, buffer);

        if (top_level == NULL) {
            top_level = object_table[i].description;
        }
    }
    print_table();
    return object_table_size;
}

/**
 * Read the trace from the specified file and put it in the trace global
 * variable. Return the length of the trace.
 * @param trace_file The file to read.
 * @return The number of trace record read or 0 upon seeing an EOF.
 */
int read_trace(FILE* trace_file) {
    // Read first the int giving the length of the trace.
    int trace_length;
    int items_read = fread(&trace_length, sizeof(int), 1, trace_file);
    if (items_read != 1) {
        if (feof(trace_file)) return 0;
        fprintf(stderr, "Failed to read trace length.\n");
        exit(3);
    }
    if (trace_length > TRACE_BUFFER_CAPACITY) {
        fprintf(stderr, "ERROR: Trace length %d exceeds capacity. File is garbled.\n", trace_length);
        exit(4);
    }
    // printf("DEBUG: Trace of length %d being converted.\n", trace_length);

    items_read = fread(&trace, sizeof(trace_record_t), trace_length, trace_file);
    if (items_read != trace_length) {
        fprintf(stderr, "Failed to read trace of length %d.\n", trace_length);
        exit(5);
    }
    return trace_length;
}