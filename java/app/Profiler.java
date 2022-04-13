/*
 * Copyright (c) 2015, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */
package app;

/**
 * Профайлер для удобного замера времени выполения кода. Замеряет текущее время при создании, конечное при вызове
 * snapshot() и отображает в лог по команде show().
 * <pre>
 * Profiler p = new Profiler(); // time A
 * ...
 * p.snapshot().show("step"); // time B, show B-A
 * ...
 * p.snapshot().show().reset(); // time C, show C-A
 * ...
 * p.snapshot().show(); // time D, show D-C
 * ...
 * </pre>
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class Profiler {

    private String title;
    private String comment;
    private long starttime;
    private long endtime;

    public Profiler(String title) {
        this.title = title;
        this.comment = null;
        this.starttime = System.currentTimeMillis();
        this.endtime = this.starttime;
    }

    public Profiler() {
        this("PROFILER");
    }

    public String getTitle() {
        return title;
    }

    public String getComment() {
        return comment;
    }

    public long getStartTime() {
        return starttime;
    }

    public long getEndTime() {
        return endtime;
    }

    public Profiler show() {
        String msg = String.format("[%s] time = %.3f ms", title, (endtime - starttime) / 1000.0);
        if (comment != null && !comment.isEmpty()) {
            msg += " (" + comment + ")";
        }
        System.out.println(msg);
        return this;
    }

    public Profiler snapshot(String comment) {
        this.endtime = System.currentTimeMillis();
        this.comment = comment;
        return this;
    }

    public Profiler snapshot() {
        return snapshot(null);
    }

    public Profiler reset() {
        this.starttime = System.currentTimeMillis();
        this.endtime = this.starttime;
        this.comment = null;
        return this;
    }
}
